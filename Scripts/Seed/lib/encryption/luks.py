"""
lib/encryption/luks.py — Thin wrappers around cryptsetup
Handles all LUKS operations: open, close, addKey, deleteKey, dump.
"""

import subprocess
import os
from typing import Optional

from common.emit import emit


def _run(cmd: list[str], input_text: str = None, timeout: int = 30) -> subprocess.CompletedProcess:
    """Run a command, return result. Caller handles errors."""
    try:
        return subprocess.run(
            cmd,
            input=input_text,
            capture_output=True,
            text=True,
            timeout=timeout
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 1, "", "command timed out")


def open_img(img_path: str, mapper_name: str, passphrase: str = None, keyfile_path: str = None) -> bool:
    """
    Open a LUKS image using either passphrase or keyfile.
    Returns True on success, False on failure.
    """
    cmd = ["sudo", "cryptsetup", "open", img_path, mapper_name]

    if keyfile_path:
        cmd.extend(["--key-file", keyfile_path])
        result = _run(cmd)
    elif passphrase:
        result = _run(cmd, input_text=passphrase)
    else:
        return False

    if result.returncode != 0:
        emit("error", f"cryptsetup open failed: {result.stderr.strip()}")
        return False

    return True


def close_img(mapper_name: str) -> bool:
    """Close a LUKS device. Returns True on success."""
    cmd = ["sudo", "cryptsetup", "close", mapper_name]
    result = _run(cmd)
    if result.returncode != 0:
        emit("error", f"cryptsetup close failed: {result.stderr.strip()}")
        return False
    return True


def add_key(
    img_path: str,
    slot_num: int,
    new_passphrase: str = None,
    auth_passphrase: str = None,
    auth_keyfile: str = None,
    new_keyfile: str = None,
    preset = None,
) -> bool:
    """
    Add a new key to a LUKS slot.
    New key: either new_passphrase (requires preset) or new_keyfile path.
    Auth: either auth_passphrase or auth_keyfile.
    Returns True on success.
    """
    if new_passphrase is not None and not new_passphrase.strip():
        from common.errors import error
        error("EMPTY_PASSPHRASE", "passphrase cannot be empty")
    if not preset and new_passphrase:
        from common.errors import error
        error("NO_PRESET", "preset required for add_key")

    cmd = [
        "sudo", "cryptsetup", "luksAddKey",
        "--key-slot", str(slot_num),
    ]

    # Add KDF params if preset given
    if preset:
        cmd.extend([
            "--pbkdf", "argon2id",
            "--pbkdf-memory", str(preset.argon2_memory // 1024),  # KiB
            "--pbkdf-force-iterations", str(preset.argon2_time),  # iterations
            "--pbkdf-parallel", str(preset.argon2_parallel),
        ])
    else:
        # For keyfile-to-keyfile operations, use weak PBKDF2
        cmd.extend(["--pbkdf", "pbkdf2"])

    cmd.append(img_path)

    # New keyfile as positional arg (cryptsetup luksAddKey <device> <new-keyfile>)
    if new_keyfile:
        cmd.append(new_keyfile)

    # Add authentication
    input_text = None
    if auth_keyfile:
        cmd.extend(["--key-file", auth_keyfile])
        if new_passphrase and not new_keyfile:
            input_text = new_passphrase
    elif auth_passphrase:
        if new_passphrase and not new_keyfile:
            input_text = f"{auth_passphrase}\n{new_passphrase}"
        else:
            input_text = auth_passphrase
    else:
        return False

    result = _run(cmd, input_text=input_text)
    return result.returncode == 0


def delete_key(img_path: str, slot_num: int, auth_keyfile: str = None, auth_passphrase: str = None) -> bool:
    """
    Delete a key from a LUKS slot.
    Authenticate with either auth_passphrase or auth_keyfile.
    Returns True on success.
    """
    cmd = ["sudo", "cryptsetup", "luksKillSlot"]

    if auth_keyfile:
        cmd.extend(["--key-file", auth_keyfile])
    elif auth_passphrase:
        pass  # passphrase via stdin below

    cmd.extend([img_path, str(slot_num)])

    input_text = auth_passphrase if auth_passphrase and not auth_keyfile else None
    result = _run(cmd, input_text=input_text)
    return result.returncode == 0


def dump(img_path: str) -> Optional[dict]:
    """
    Dump LUKS header info. Parse and return dict of slot states.
    Returns dict with 'active_slots' list or None on error.
    """
    cmd = ["sudo", "cryptsetup", "luksDump", img_path]
    result = _run(cmd)
    if result.returncode != 0:
        return None

    # Parse output to find active slots (LUKS2 format: "  N: luks2")
    active_slots = []
    in_keyslots = False
    for line in result.stdout.split("\n"):
        if line.strip() == "Keyslots:":
            in_keyslots = True
            continue
        if in_keyslots:
            # Exit section on non-indented, non-empty lines (next section header)
            if line and not line[0].isspace():
                break
            # Match slot entries: "  N: luks2"
            stripped = line.strip()
            if stripped and stripped[0].isdigit() and ": luks2" in stripped:
                try:
                    slot_num = int(stripped.split(":")[0].strip())
                    active_slots.append(slot_num)
                except ValueError:
                    pass

    return {"active_slots": active_slots}


def try_unlock_priority(img_path: str, mapper_name: str, mnt: str) -> bool:
    """
    Try to unlock the image using UNLOCK_PRIORITY order.
    Returns True on first success, False if all attempts fail.
    """
    from lib.variables.general import UNLOCK_PRIORITY, LUKS_DEFAULT_KEY
    from lib.encryption.keyfile import read_keyfile
    from lib.encryption.derive import get_or_derive_passphrase
    from lib.encryption.presets import load_preset

    for method in UNLOCK_PRIORITY:
        try:
            if method == "hardcoded":
                if open_img(img_path, mapper_name, passphrase=LUKS_DEFAULT_KEY):
                    return True
            elif method == "keyfile_a":
                keyfile_a = read_keyfile(mnt, "a")
                if keyfile_a:
                    # Write keyfile to temp location
                    import tempfile
                    with tempfile.NamedTemporaryFile(delete=False) as f:
                        f.write(keyfile_a)
                        temp_path = f.name
                    try:
                        if open_img(img_path, mapper_name, keyfile_path=temp_path):
                            return True
                    finally:
                        os.remove(temp_path)
            elif method == "derived":
                # Load preset, derive key
                preset = load_preset("medium", mnt)  # Use default preset for derivation
                if preset:
                    derived_key = get_or_derive_passphrase(mnt, preset)
                    if open_img(img_path, mapper_name, passphrase=derived_key):
                        return True
            elif method == "passkey":
                # User-interactive: prompt for passphrase
                try:
                    passphrase = input("Enter LUKS passphrase: ")
                    if not passphrase or not passphrase.strip():
                        from common.emit import emit
                        emit("log", "empty passphrase rejected")
                        continue
                    if open_img(img_path, mapper_name, passphrase=passphrase):
                        return True
                except EOFError:
                    pass
        except Exception:
            continue

    return False
