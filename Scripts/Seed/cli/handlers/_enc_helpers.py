"""
cli/handlers/_enc_helpers.py — encryption internal helpers (auth, slot resolution)
"""

import os
from common.emit import emit
from common.errors import error

from lib.encryption.presets import load_preset, list_presets
from lib.encryption.slots import get_slot_by_name
from lib.encryption.guard import check_slot_is_user_slot, check_no_ambiguous_names
from lib.encryption.keyfile import read_keyfile
from lib.encryption.luks import add_key as luks_add_key, delete_key as luks_delete_key
from lib.variables.general import LUKS_DEFAULT_KEY


def _get_enc_mnt() -> str:
    from cli.handlers._core import _mnt
    mnt = _mnt()
    if not mnt:
        error("NO_IMG", "no image selected", "use 'sd select <path>' first")
    return mnt


def _resolve_preset(preset_name: str, mnt: str):
    from orchestration.settings import get_rule
    if preset_name:
        preset = load_preset(preset_name, mnt)
        if not preset:
            available = [p.name for p in list_presets(mnt)]
            error("PRESET_NOT_FOUND", f"preset '{preset_name}' not found",
                  f"available: {', '.join(available)}")
        return preset
    default_name = get_rule("encryption_default_preset") or "medium"
    preset = load_preset(default_name, mnt)
    if not preset:
        error("PRESET_ERROR", f"default preset '{default_name}' not available")
    return preset


def _resolve_slot(slot_or_name: str, mnt: str) -> int:
    try:
        slot_num = int(slot_or_name)
        check_slot_is_user_slot(slot_num)
        return slot_num
    except ValueError:
        pass
    result = get_slot_by_name(mnt, slot_or_name)
    if result:
        check_no_ambiguous_names(mnt, slot_or_name)
        return result[0]
    error("SLOT_NOT_FOUND", f"slot or name '{slot_or_name}' not found")


def _get_img_path() -> str:
    import tomllib, subprocess, json
    mnt = _get_enc_mnt()
    meta_path = os.path.join(mnt, "meta.toml")
    try:
        with open(meta_path, "rb") as f:
            meta = tomllib.load(f)
        stored = meta.get("img_path", "")
        if stored and os.path.isfile(stored):
            return stored
        mapper = meta.get("mapper", "")
        if mapper:
            result = subprocess.run(
                ["losetup", "--list", "--output", "NAME,BACK-FILE", "--noheadings", "--json"],
                capture_output=True, text=True, timeout=5
            )
            try:
                for dev in json.loads(result.stdout).get("loopdevices", []):
                    bf = dev.get("back-file", "")
                    if bf and os.path.isfile(bf):
                        return bf
            except (json.JSONDecodeError, KeyError):
                for line in result.stdout.splitlines():
                    parts = line.split()
                    if len(parts) >= 2:
                        p = ' '.join(parts[1:])
                        if p and os.path.isfile(p):
                            return p
    except Exception:
        pass
    error("IMG_PATH_NOT_FOUND", "could not locate .img file for selected session")


def _try_auth_add(img_path, slot_num, new_passphrase, preset, mnt):
    import tempfile
    keyfile_a = read_keyfile(mnt, "a")
    if keyfile_a:
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(keyfile_a); tmp = f.name
        try:
            if luks_add_key(img_path, slot_num, new_passphrase, auth_keyfile=tmp, preset=preset):
                return True
        finally:
            os.remove(tmp)
    if luks_add_key(img_path, slot_num, new_passphrase, auth_passphrase=LUKS_DEFAULT_KEY, preset=preset):
        return True
    return False


def _try_auth_delete(img_path, slot_num, mnt):
    import tempfile
    keyfile_a = read_keyfile(mnt, "a")
    if keyfile_a:
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(keyfile_a); tmp = f.name
        try:
            if luks_delete_key(img_path, slot_num, auth_keyfile=tmp):
                return True
        finally:
            os.remove(tmp)
    if luks_delete_key(img_path, slot_num, auth_passphrase=LUKS_DEFAULT_KEY):
        return True
    return False
