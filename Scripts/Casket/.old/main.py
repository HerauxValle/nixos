#!/usr/bin/env python3

# cas - encrypted vault manager
#
# Usage:  cas <vault> <action> [options]
#         cas <action> [options]          (for global actions)

import os, sys, subprocess, hashlib, tempfile, json, shutil, shlex
from pathlib import Path

if os.geteuid() != 0:
    print("[i] elevating to sudo (if this fails, run with sudo manually)", file=sys.stderr)
    os.execvp("sudo", ["sudo"] + sys.argv)

# ---------- removable keyfile mount helper ----------

from contextlib import contextmanager

@contextmanager
def ensure_keyfile_mounted(kf_path_str):
    """
    If --keyfile lives on a removable mount (/run/media/* or /media/*):
      - device not present  → yield None (caller skips keyfile)
      - present, mounted    → yield path as-is, don't unmount after
      - present, unmounted  → mount it, yield path, unmount after
    If keyfile is on a permanent disk → yield path unchanged.
    """
    if not kf_path_str:
        yield None
        return

    kf = Path(kf_path_str)

    # use the raw path string to detect removable — don't resolve/walk,
    # because under sudo the mountpoint dir may not exist yet
    kf_str = str(kf)
    removable = kf_str.startswith("/run/media/") or kf_str.startswith("/media/")

    if not removable:
        yield kf_path_str
        return

    # extract the mountpoint prefix: /run/media/user/LABEL
    # parts: ['/', 'run', 'media', 'user', 'LABEL', ...]
    parts = kf.parts
    if len(parts) < 5:
        yield kf_path_str
        return
    mount_prefix = str(Path(*parts[:5]))  # /run/media/user/LABEL
    probe_str = mount_prefix

    def find_device(devs):
        """Returns (uuid, mountpoint_or_None) if label/uuid matches, else (None, None)"""
        for d in devs:
            label = d.get("label") or ""
            uuid_ = d.get("uuid") or ""
            if (label and label in probe_str) or (uuid_ and uuid_ in probe_str):
                return uuid_, d.get("mountpoint")  # mountpoint may be None = unmounted
            if d.get("children"):
                result = find_device(d["children"])
                if result[0] is not None:
                    return result
        return None, None

    # Retry for up to 30s — at login, udev may not have enumerated the device yet
    import time as _time
    _deadline = _time.monotonic() + 30
    found_uuid, current_mount = None, None
    while True:
        data = _lsblk_json()
        found_uuid, current_mount = find_device(data.get("blockdevices", []))
        if found_uuid is not None or _time.monotonic() >= _deadline:
            break
        _time.sleep(1)

    if found_uuid is None:
        if not QUIET:
            print(f"[!] keyfile device not found (drive unplugged?), skipping keyfile", file=sys.stderr)
        yield None
        return

    if current_mount:
        # already mounted — reconstruct keyfile path under actual mountpoint
        rel = kf.parts[len(Path(current_mount).parts):]
        yield str(Path(current_mount).joinpath(*rel))
        return

    # device present but not mounted — mount it
    uuid = found_uuid
    dev = f"/dev/disk/by-uuid/{uuid}"

    if not QUIET:
        print(f"[i] mounting removable device {uuid} ...", file=sys.stderr)
    r = subprocess.run(["udisksctl", "mount", "--no-user-interaction", "-b", dev],
                       capture_output=True, text=True)
    if r.returncode != 0:
        if not QUIET:
            print(f"[!] mount failed: {r.stderr.strip()}, skipping keyfile", file=sys.stderr)
        yield None
        return

    import re as _re
    m = _re.search(r"at (.+)$", r.stdout.strip())
    if m:
        actual_mount = m.group(1)
        rel = kf.parts[len(parts[:5]):]
        actual_kf = str(Path(actual_mount).joinpath(*rel))
    else:
        actual_kf = kf_path_str

    try:
        yield actual_kf
    finally:
        if not QUIET:
            print(f"[i] unmounting {uuid} ...", file=sys.stderr)
        subprocess.run(["udisksctl", "unmount", "--no-user-interaction", "-b", dev],
                       capture_output=True)

def _lsblk_json():
    """Run lsblk as the real user (not root) so udisks mounts are visible."""
    import json as _json
    real_uid = int(os.environ.get("SUDO_UID", os.getuid()))
    real_gid = int(os.environ.get("SUDO_GID", os.getgid()))
    def drop():
        os.setgid(real_gid)
        os.setuid(real_uid)
    r = subprocess.run(
        ["lsblk", "-J", "-o", "NAME,UUID,LABEL,MOUNTPOINT"],
        capture_output=True, text=True, preexec_fn=drop
    )
    if r.returncode != 0:
        return {}
    try:
        return _json.loads(r.stdout)
    except Exception:
        return {}

def _find_uuid_for_mount_prefix(path_str):
    data = _lsblk_json()

    def search(devices):
        for d in devices:
            uuid  = d.get("uuid") or ""
            label = d.get("label") or ""
            mount = d.get("mountpoint") or ""
            if (label and label in path_str) or (uuid and uuid in path_str):
                return uuid   # found it — mounted or not, return uuid either way
            if d.get("children"):
                result = search(d["children"])
                if result is not None:
                    return result
        return None

    return search(data.get("blockdevices", []))

# ---------- config ----------

MAPPER_PREFIX = "casvault"

KDF_PRESETS = {
    "light":   ["--pbkdf-memory", "128000",  "--pbkdf-parallel", "2"],
    "medium":  ["--pbkdf-memory", "512000",  "--pbkdf-parallel", "4"],
    "hard":    ["--pbkdf-memory", "1024000", "--pbkdf-parallel", "4"],
    "extreme": ["--pbkdf-memory", "2048000", "--pbkdf-parallel", "8"],
}

KDF_ITERATIONS = {
    "light":   "50",
    "medium":  "20",
    "hard":    "9",
    "extreme": "5",
}

MAGIC = b"IMGVLT01"

# ---------- trailing metadata ----------
# Format: [JSON bytes][4-byte big-endian length][MAGIC]

def meta_read(img):
    try:
        with open(img, "rb") as f:
            f.seek(-len(MAGIC), 2)
            if f.read(len(MAGIC)) != MAGIC:
                return {}
            f.seek(-(len(MAGIC) + 4), 2)
            size = int.from_bytes(f.read(4), "big")
            f.seek(-(len(MAGIC) + 4 + size), 2)
            data = f.read(size)
        return json.loads(data.decode())
    except Exception:
        return {}

def meta_strip(img):
    try:
        with open(img, "rb+") as f:
            f.seek(-len(MAGIC), 2)
            if f.read(len(MAGIC)) != MAGIC:
                return
            f.seek(-(len(MAGIC) + 4), 2)
            size = int.from_bytes(f.read(4), "big")
            f.seek(-(len(MAGIC) + 4 + size), 2)
            f.truncate()
    except Exception:
        pass

def meta_write(img, data):
    payload = json.dumps(data).encode()
    meta_strip(img)
    with open(img, "ab") as f:
        f.write(payload)
        f.write(len(payload).to_bytes(4, "big"))
        f.write(MAGIC)

# ---------- utils ----------

QUIET      = False  # set via --no-log
NO_CONFIRM = False  # set via --no-confirm

def run(cmd, input=None, check=True):
    return subprocess.run(cmd, input=input, check=check)

def log(*args, **kwargs):
    if not QUIET:
        print(*args, **kwargs)

def ask(prompt, default=None, secret=False):
    try:
        if secret:
            import getpass
            val = getpass.getpass(f"{prompt}: " if not QUIET else "")
        else:
            suffix = f" [{default}]" if default else ""
            val = input(f"{prompt}{suffix}: " if not QUIET else "").strip()
    except KeyboardInterrupt:
        if not QUIET:
            log("\n[x] aborted")
        sys.exit(1)
    return val or default

def user_ids():
    u   = os.environ.get("SUDO_USER") or os.environ.get("USER")
    uid = int(subprocess.check_output(["id", "-u", u]).decode())
    gid = int(subprocess.check_output(["id", "-g", u]).decode())
    return uid, gid

def tmp_keyfile(data):
    tf = tempfile.NamedTemporaryFile(delete=False)
    tf.write(data)
    tf.close()
    os.chmod(tf.name, 0o600)
    return tf.name

def combined_secret(pw, kf_bytes):
    return hashlib.sha256(pw.encode() + kf_bytes).hexdigest().encode()

def die(msg):
    if not QUIET:
        log(f"[x] {msg}")
    sys.exit(1)

# ---------- path resolution ----------

def find_img(name, path_override=None):
    if path_override:
        base = Path(path_override).resolve()
        img  = base / f"{name}.img"
        if not img.exists():
            die(f"vault '{name}' not found at {img}\n"
                f"    Hint: check the path or run 'cas list' to see all vaults.")
        return img, base

    for d in [Path.cwd()] + list(Path.cwd().parents)[:4]:
        img = d / f"{name}.img"
        if img.exists():
            return img, d

    die(f"vault '{name}' not found (searched cwd and 4 levels up)\n"
        f"    Hint: run 'cas list' to see all vaults, or cd to where it lives.")

def resolve(base, name):
    return base / f"{name}.img", base / name, f"{MAPPER_PREFIX}_{name}"

# ---------- LUKS helpers ----------

def open_luks(img, mapper, secret):
    tf = tmp_keyfile(secret)
    try:
        run(["cryptsetup", "open", "--key-file", tf, str(img), mapper])
    except subprocess.CalledProcessError:
        die("wrong passphrase or keyfile — could not unlock vault")
    finally:
        os.unlink(tf)
    return f"/dev/mapper/{mapper}"

import re as _re

def _luks_used_slots(img):
    """Return set of active slot numbers from luksDump."""
    out = subprocess.run(["cryptsetup", "luksDump", str(img)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode()
    used = set()
    # LUKS2: keyslot section looks like:
    #   Keyslots:
    #     0: luks2
    #     1: luks2
    # Also handle LUKS1: "Key Slot 0: ENABLED"
    for line in out.splitlines():
        m = _re.match(r'\s+(\d+):\s+(?:luks2|enabled)\b', line, _re.IGNORECASE)
        if m:
            used.add(int(m.group(1)))
        m2 = _re.match(r'\s*Key Slot\s+(\d+):\s+ENABLED', line, _re.IGNORECASE)
        if m2:
            used.add(int(m2.group(1)))
    return used

def luks_find_used_slot(img, secret):
    """Return the slot number that unlocks with secret (test each active slot)."""
    tf = tmp_keyfile(secret)
    try:
        active = _luks_used_slots(img)
        for slot in sorted(active):
            r = subprocess.run(
                ["cryptsetup", "open", "--test-passphrase",
                 "--key-slot", str(slot), "--key-file", tf, str(img)],
                capture_output=True)
            if r.returncode == 0:
                return slot
    finally:
        os.unlink(tf)
    return None

def luks_find_free_slot(img, exclude=None):
    """Return first unused slot, optionally excluding one slot number."""
    used = _luks_used_slots(img)
    for s in range(32):
        if s not in used and s != exclude:
            return s
    return None

def luks_add_key(img, auth_secret, new_secret, strength=None, slot=None):
    tf_auth = tmp_keyfile(auth_secret)
    tf_new  = tmp_keyfile(new_secret)
    try:
        cmd = ["cryptsetup", "luksAddKey", "--batch-mode",
               "--key-file", tf_auth]
        if strength and strength in KDF_PRESETS:
            cmd += [
                "--pbkdf", "argon2id",
                *KDF_PRESETS[strength],
                "--pbkdf-force-iterations", KDF_ITERATIONS[strength]
            ]
        if slot is not None:
            cmd += ["--key-slot", str(slot)]
        cmd += [str(img), tf_new]
        run(cmd)
    finally:
        os.unlink(tf_auth); os.unlink(tf_new)

def luks_remove_slot(img, slot, auth_secret):
    """Remove a LUKS slot by number. Requires any valid key for authorization."""
    tf = tmp_keyfile(auth_secret)
    try:
        run(["cryptsetup", "luksKillSlot", "--batch-mode",
             "--key-file", tf, str(img), str(slot)])
    finally:
        os.unlink(tf)

def luks_test(img, secret):
    tf = tmp_keyfile(secret)
    try:
        r = subprocess.run(
            ["cryptsetup", "open", "--test-passphrase", "--key-file", tf, str(img)],
            capture_output=True)
        return r.returncode == 0
    finally:
        os.unlink(tf)

def slot_cycle(img, old_secret, new_secret, strength=None):
    """Swap LUKS key safely: find old slot, add new to a specific free slot,
    verify new works, then kill old slot by number using the new key as auth."""
    old_slot = luks_find_used_slot(img, old_secret)
    if old_slot is None:
        die("current passphrase did not match any LUKS slot")

    new_slot = luks_find_free_slot(img, exclude=old_slot)
    if new_slot is None:
        die("no free LUKS slots available")

    log(f"  [1/3] writing new key to slot {new_slot}"
        + (f" (strength={strength})" if strength else "") + " ...")
    luks_add_key(img, old_secret, new_secret, strength=strength, slot=new_slot)

    log("  [2/3] verifying ...")
    if not luks_test(img, new_secret):
        try:
            luks_remove_slot(img, new_slot, old_secret)
        except Exception:
            pass
        die("verification failed — rolled back, old key is still valid")

    log(f"  [3/3] removing old key from slot {old_slot} ...")
    # authenticate the kill with the new key (old is being removed)
    luks_remove_slot(img, old_slot, new_secret)

def get_secret(img, pw, kf_override=None, _meta=None):
    """Return (secret_bytes, meta). Handles 2FA and encryption=off transparently.
    Pass _meta if you already read it (e.g. before meta_strip)."""
    meta = _meta if _meta is not None else meta_read(img)

    # encryption=off: autokey is the canonical secret — use it directly
    if meta.get("encrypted") is False and "_autokey" in meta and not kf_override:
        import base64 as _b64
        return _b64.b64decode(meta["_autokey"].encode()), meta

    has_2fa = "keyfile" in meta
    if not has_2fa:
        return pw.encode(), meta

    kf_path = Path(kf_override or meta["keyfile"]).resolve()
    if not kf_path.exists():
        if QUIET or kf_override:
            die(f"keyfile not found: {kf_path}")
        log(f"  [!] keyfile not found at cached path: {kf_path}")
        kf_input = ask("  keyfile path")
        if not kf_input:
            die("keyfile is required for this 2FA vault")
        kf_path = Path(kf_input).resolve()
        if not kf_path.exists():
            die(f"keyfile not found: {kf_path}")

    if not kf_path.is_file():
        die(f"keyfile is not a file: {kf_path}")

    if str(kf_path) != meta.get("keyfile"):
        meta["keyfile"] = str(kf_path)

    return combined_secret(pw, kf_path.read_bytes()), meta

def resolve_keyfile(cached_path_str, meta, img):
    """Resolve a keyfile path, prompting interactively if not found.
    Updates meta["keyfile"] and persists it to img if the path changed.
    Returns a Path. Dies if file still not found after prompt."""
    kf_path = Path(cached_path_str).resolve()
    if kf_path.exists():
        return kf_path
    if QUIET:
        die(f"keyfile not found: {kf_path}")
    log(f"  [!] keyfile not found at cached path: {kf_path}")
    kf_input = ask("  keyfile path")
    if not kf_input:
        die("keyfile is required — cannot continue without it")
    kf_path = Path(kf_input).resolve()
    if not kf_path.exists():
        die(f"keyfile not found: {kf_path}")
    # update cached path in meta and persist immediately
    meta["keyfile"] = str(kf_path)
    meta_write(img, meta)
    log("  [i] updated cached keyfile path")
    return kf_path

# ---------- commands ----------

def cmd_create(name, base, size, pw, strength):
    img, _, _ = resolve(base, name)
    if img.exists():
        die(f"vault '{name}' already exists at {img}")
    if size is None:
        size_str = ask("size (e.g. 1G, 500M, 2048)", default="1G")
        size = parse_size(size_str or "1G")
    if not pw:
        import secrets as _sec, string as _str
        alphabet = _str.ascii_letters + _str.digits + "!@#$%^&*-_=+?"
        pw = ''.join(_sec.choice(alphabet) for _ in range(28))
        log(f"  [i] generated passphrase: {pw}")
        log(f"      Save this — it cannot be recovered!")
    log(f"[cas] creating vault '{name}' ({size} MiB, strength={strength}) ...")
    run(["truncate", "-s", f"{size}M", str(img)])
    try:
        tf = tmp_keyfile(pw.encode())
        try:
            run([
                "cryptsetup", "luksFormat", "--batch-mode",
                "--pbkdf", "argon2id",
                *KDF_PRESETS[strength],
                "--pbkdf-force-iterations", KDF_ITERATIONS[strength],
                str(img), "--key-file", tf
            ])
        finally:
            os.unlink(tf)
        uid, gid = user_ids()
        os.chown(img, uid, gid)
        _udisks_loop_setup(img)
        log(f"[\u2713] vault created: {img}")
        log(f"    open it with:  cas {name} open")
    except (SystemExit, Exception):
        img.unlink(missing_ok=True)
        raise

def cmd_open(name, base, pw, kf_override=None):
    img, mnt, mapper = resolve(base, name)
    if mnt.is_mount():
        log(f"[i] '{name}' is already open at {mnt}")
        return
    # clean up stale mapper if it exists but mountpoint isn't mounted
    if Path(f"/dev/mapper/{mapper}").exists():
        subprocess.run(["cryptsetup", "close", mapper], stderr=subprocess.DEVNULL)
    mnt.mkdir(exist_ok=True)
    meta = meta_read(img)
    # encryption UX bypass: auto-unlock without prompting
    if meta.get("encrypted") is False and "_autokey" in meta:
        import base64 as _b64
        secret = _b64.b64decode(meta["_autokey"].encode())
        log(f"[cas] opening '{name}' ...")
        meta_strip(img)
        try:
            dev = open_luks(img, mapper, secret)
        finally:
            meta_write(img, meta)
        size_mb = img.stat().st_size // (1024 * 1024)
        fs = subprocess.run(["blkid", dev], stdout=subprocess.PIPE).stdout.decode()
        if "btrfs" not in fs:
            log("  [i] first open — formatting filesystem ...")
            run(["mkfs.btrfs", "-f", "-L", f"{name} [{_size_label(size_mb)}]", dev])
        run(["mount", dev, str(mnt)])

        log("  [i] verifying filesystem size ...")
        subprocess.run(["btrfs", "filesystem", "resize", "max", str(mnt)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        _set_btrfs_label(mnt, name, size_mb)
        _udev_retrigger(dev)

        uid, gid = user_ids()
        os.chown(mnt, uid, gid)
        _maybe_auto_backup(name, mnt, meta)
        log(f"[✓] '{name}' is open at {mnt}")
        return

    secret, meta = get_secret(img, pw, kf_override)
    updated_meta = meta != meta_read(img)
    log(f"[cas] opening '{name}' ...")
    meta_strip(img)
    try:
        dev = open_luks(img, mapper, secret)
    finally:
        meta_write(img, meta)
    if updated_meta:
        log("  [i] updated cached keyfile path")
    size_mb = img.stat().st_size // (1024 * 1024)
    fs = subprocess.run(["blkid", dev], stdout=subprocess.PIPE).stdout.decode()
    if "btrfs" not in fs:
        log("  [i] first open — formatting filesystem ...")
        run(["mkfs.btrfs", "-f", "-L", f"{name} [{_size_label(size_mb)}]", dev])
    run(["mount", dev, str(mnt)])

    log("  [i] verifying filesystem size ...")
    subprocess.run(["btrfs", "filesystem", "resize", "max", str(mnt)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _set_btrfs_label(mnt, name, size_mb)
    _udev_retrigger(dev)

    uid, gid = user_ids()
    os.chown(mnt, uid, gid)
    _maybe_auto_backup(name, mnt, meta)
    log(f"[✓] '{name}' is open at {mnt}")

def cmd_close(name, base):
    _, mnt, mapper = resolve(base, name)
    if not mnt.is_mount():
        log(f"[i] '{name}' is already closed")
        return
    log(f"[cas] closing '{name}' ...")
    subprocess.run(["umount", str(mnt)],           stderr=subprocess.DEVNULL)
    subprocess.run(["cryptsetup", "close", mapper], stderr=subprocess.DEVNULL)
    try:
        if mnt.exists() and not mnt.is_mount():
            mnt.rmdir()
    except OSError:
        pass
    log(f"[\u2713] '{name}' closed")

def cmd_toggle(name, base, pw=None, kf_override=None):
    img, mnt, _ = resolve(base, name)
    if mnt.is_mount():
        cmd_close(name, base)
    else:
        meta = meta_read(img)
        if meta.get("encrypted") is False and "_autokey" in meta:
            cmd_open(name, base, "", kf_override)
        else:
            if not pw:
                pw = ask("passphrase", secret=True)
            cmd_open(name, base, pw, kf_override)

def cmd_info(name, base):
    img, mnt, _ = resolve(base, name)
    if not img.exists():
        die(f"vault '{name}' not found")
    meta     = meta_read(img)
    size_mb  = img.stat().st_size // (1024 * 1024)
    mounted  = "yes  ->  " + str(mnt) if mnt.is_mount() else "no"
    has_2fa  = ("yes  (keyfile: " + meta["keyfile"] + ")") if "keyfile" in meta else "no"
    slot_out = subprocess.run(["cryptsetup", "luksDump", str(img)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode()
    slots = slot_out.count("ENABLED")
    log(f"\n  vault     {img}\n  size      {size_mb} MiB\n  open      {mounted}\n  2fa       {has_2fa}\n  slots     {slots} active\n")

def cmd_passwd(name, base, old_pw=None, new_pw=None, strength=None):
    img, mnt, _ = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if mnt.is_mount():   die(f"vault is open — close it first:  cas {name} close")
    if not old_pw:
        old_pw = ask("current passphrase", secret=True)
    if not new_pw:
        new_pw      = ask("new passphrase",     secret=True)
        confirm     = ask("confirm new passphrase", secret=True)
        if new_pw != confirm: die("passphrases don't match")
    if not new_pw: die("passphrase cannot be empty")
    meta    = meta_read(img)
    has_2fa = "keyfile" in meta
    if has_2fa:
        kf_path    = resolve_keyfile(meta["keyfile"], meta, img)
        kf_bytes   = kf_path.read_bytes()
        old_secret = combined_secret(old_pw, kf_bytes)
        new_secret = combined_secret(new_pw, kf_bytes)
    else:
        old_secret = old_pw.encode()
        new_secret = new_pw.encode()
    strength_label = strength or "unchanged"
    log(f"[cas] changing passphrase for '{name}' (strength={strength_label}) ...")
    meta_strip(img)
    try:
        slot_cycle(img, old_secret, new_secret, strength=strength)
    except SystemExit:
        meta_write(img, meta)  # restore meta before propagating
        raise
    # update _autokey if encryption UX bypass is active
    if meta.get("encrypted") is False and "_autokey" in meta:
        import base64 as _b64
        meta["_autokey"] = _b64.b64encode(new_secret).decode()
        log("  [i] updated stored autokey (encryption off mode)")
    meta_write(img, meta)
    log(f"[✓] passphrase updated")

def cmd_2fa_on(name, base, pw):
    img, mnt, _ = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if mnt.is_mount():   die(f"vault is open — close it first:  cas {name} close")
    meta = meta_read(img)
    if "keyfile" in meta:
        die(f"2FA is already enabled\n    Run 'cas {name} 2fa off' first.")
    # derive old_secret the same way open does — respects encryption=off autokey
    old_secret, _ = get_secret(img, pw, _meta=meta)
    import secrets as _s
    kf = img.parent / f"{name}.key"
    kf.write_bytes(_s.token_bytes(64))
    os.chmod(kf, 0o600)
    uid, gid = user_ids()
    os.chown(kf, uid, gid)
    log(f"  [i] generated keyfile: {kf}")
    log(f"      Back this up — losing it means losing access to the vault.")
    kf_bytes   = kf.read_bytes()
    new_secret = combined_secret(pw, kf_bytes)
    log(f"[cas] enabling 2FA on '{name}' ...")
    meta_strip(img)
    new_meta = {"keyfile": str(kf)}
    if meta.get("encrypted") is False:
        import base64 as _b64
        new_meta["encrypted"] = False
        new_meta["_autokey"]  = _b64.b64encode(new_secret).decode()
    try:
        slot_cycle(img, old_secret, new_secret, strength=None)
    except SystemExit:
        meta_write(img, meta)
        # clean up orphaned keyfile on failure
        try: kf.unlink()
        except OSError: pass
        raise
    meta_write(img, new_meta)
    log(f"[✓] 2FA enabled — keyfile: {kf}")
    log(f"    You now need BOTH your passphrase AND that keyfile to open this vault.")

def cmd_2fa_off(name, base, pw):
    img, mnt, _ = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if mnt.is_mount():   die(f"vault is open — close it first:  cas {name} close")
    meta = meta_read(img)
    if "keyfile" not in meta:
        die("2FA is not enabled on this vault")
    kf_path    = resolve_keyfile(meta["keyfile"], meta, img)
    kf_bytes   = kf_path.read_bytes()
    old_secret = combined_secret(pw, kf_bytes)
    new_secret = pw.encode()
    log(f"[cas] disabling 2FA on '{name}' ...")
    meta_strip(img)
    new_meta = {}
    # if encryption bypass was active, update the autokey to the new (pw-only) secret
    if meta.get("encrypted") is False:
        import base64 as _b64
        new_meta["encrypted"] = False
        new_meta["_autokey"]  = _b64.b64encode(new_secret).decode()
    try:
        slot_cycle(img, old_secret, new_secret, strength=None)
    except SystemExit:
        meta_write(img, meta)
        raise
    kf_path.unlink()
    meta_write(img, new_meta)
    log(f"[\u2713] 2FA disabled \u2014 passphrase alone is sufficient again")
    log(f"  [i] keyfile deleted: {kf_path}")


SNAP_DIR = ".cas-snapshots"
AUTO_SNAP_PREFIX = "auto-"

def _snap_root(mnt):
    return mnt / SNAP_DIR

def _auto_snap_name():
    import datetime
    now = datetime.datetime.now()
    return AUTO_SNAP_PREFIX + now.strftime("%H:%M:%S-[%d-%m-%Y]")

def _snap_list_sorted(mnt, *, auto: bool):
    snap_root = _snap_root(mnt)
    if not snap_root.exists():
        return []
    snaps = []
    try:
        for s in snap_root.iterdir():
            if not s.is_dir():
                continue
            is_auto = s.name.startswith(AUTO_SNAP_PREFIX)
            if is_auto == auto:
                snaps.append(s)
    except Exception:
        return []
    return sorted(snaps, key=lambda s: s.stat().st_mtime)

def _backup_auto_prune(mnt, keep):
    """Delete oldest auto snapshots until count <= keep."""
    auto_snaps = _snap_list_sorted(mnt, auto=True)
    excess = len(auto_snaps) - keep
    if excess <= 0:
        return
    for snap in auto_snaps[:excess]:
        try:
            subprocess.run(["btrfs", "subvolume", "delete", str(snap)],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            log(f"  [i] auto-backup pruned: {snap.name}")
        except Exception as e:
            log(f"  [!] could not prune auto-backup '{snap.name}': {e}")

def _maybe_auto_backup(name, mnt, meta):
    """Create a timestamped auto snapshot and prune to keep limit if enabled in meta."""
    if not meta.get("backup_auto"):
        return
    keep = int(meta.get("backup_auto_keep", 3))
    snap_root = _snap_root(mnt)
    snap_root.mkdir(exist_ok=True)
    snap_name = _auto_snap_name()
    dest = snap_root / snap_name
    try:
        subprocess.run(["btrfs", "subvolume", "snapshot", "-r", str(mnt), str(dest)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log(f"  [i] auto-backup created: {snap_name}")
    except Exception as e:
        log(f"  [!] auto-backup failed: {e}")
        return
    _backup_auto_prune(mnt, keep)

def cmd_backup_create(name, base, snap_name):
    img, mnt, _ = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if not mnt.is_mount(): die(f"vault is closed — open it first:  cas {name} open")
    snap_root = _snap_root(mnt)
    snap_root.mkdir(exist_ok=True)
    dest = snap_root / snap_name
    if dest.exists(): die(f"snapshot '{snap_name}' already exists — pick a different name")
    run(["btrfs", "subvolume", "snapshot", "-r", str(mnt), str(dest)])
    uid, gid = user_ids()
    os.chown(snap_root, uid, gid)
    log(f"[\u2713] snapshot '{snap_name}' created inside vault")

def _snap_ctime(snap_path):
    """Get btrfs snapshot creation time, fallback to mtime."""
    try:
        out = subprocess.check_output(
            ["btrfs", "subvolume", "show", str(snap_path)],
            stderr=subprocess.DEVNULL).decode()
        for line in out.splitlines():
            if "Creation time:" in line:
                parts = line.split(":", 1)[1].strip().split()
                return f"{parts[0]} {parts[1]}"
    except Exception:
        pass
    try:
        import datetime
        t = snap_path.stat().st_mtime
        return datetime.datetime.fromtimestamp(t).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return "unknown"

def cmd_backup_list(name, base):
    img, mnt, _ = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if not mnt.is_mount(): die(f"vault is closed — open it first:  cas {name} open")
    meta = meta_read(img)
    manual = list(reversed(_snap_list_sorted(mnt, auto=False)))
    auto   = list(reversed(_snap_list_sorted(mnt, auto=True)))
    if not manual and not auto:
        log(f"  no snapshots yet — create one with:  cas {name} backup create <name>")
        return
    if manual:
        log(f"  manual snapshots (newest first):")
        for s in manual:
            log(f"    {s.name}  [{_snap_ctime(s)}]")
    if auto:
        keep = int(meta.get("backup_auto_keep", 3))
        status = "enabled" if meta.get("backup_auto") else "disabled"
        log(f"  auto-backups [{status}, keep={keep}] (newest first):")
        for s in auto:
            log(f"    {s.name}  [{_snap_ctime(s)}]")

def cmd_backup_restore(name, base, snap_name):
    img, mnt, _ = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if not mnt.is_mount(): die(f"vault is closed — open it first:  cas {name} open")
    src = _snap_root(mnt) / snap_name
    if not src.exists(): die(f"snapshot '{snap_name}' not found — run 'cas {name} backup list'")
    if QUIET or NO_CONFIRM:
        confirm = name
    else:
        log(f"  [!] All current vault contents will be replaced with snapshot '{snap_name}'.")
        confirm = ask(f"  Type the vault name '{name}' to confirm")
    if confirm != name: die("aborted")
    staging = mnt / f".cas-restore-{snap_name}"
    run(["btrfs", "subvolume", "snapshot", str(src), str(staging)])
    for item in list(mnt.iterdir()):
        if item.name in (SNAP_DIR, staging.name): continue
        try:
            subprocess.run(["btrfs", "subvolume", "delete", str(item)], stderr=subprocess.DEVNULL)
        except Exception:
            pass
        if item.exists():
            shutil.rmtree(str(item)) if item.is_dir() else item.unlink(missing_ok=True)
    for item in list(staging.iterdir()):
        shutil.move(str(item), str(mnt / item.name))
    subprocess.run(["btrfs", "subvolume", "delete", str(staging)], stderr=subprocess.DEVNULL)
    log(f"[\u2713] vault restored from snapshot '{snap_name}'")

def cmd_backup_delete(name, base, snap_name):
    img, mnt, _ = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if not mnt.is_mount(): die(f"vault is closed — open it first:  cas {name} open")
    snap = _snap_root(mnt) / snap_name
    if not snap.exists(): die(f"snapshot '{snap_name}' not found — run 'cas {name} backup list'")
    run(["btrfs", "subvolume", "delete", str(snap)])
    log(f"[\u2713] snapshot '{snap_name}' deleted")

def cmd_backup_auto_enable(name, base, keep):
    img, mnt, _ = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if mnt.is_mount(): die(f"vault is open — close it first:  cas {name} close")
    meta = meta_read(img)
    meta["backup_auto"] = True
    meta["backup_auto_keep"] = keep
    meta_strip(img)
    meta_write(img, meta)
    log(f"[✓] auto-backup enabled for '{name}' (keep={keep})")
    log(f"    a timestamped snapshot will be created each time the vault is opened")

def cmd_backup_auto_disable(name, base):
    img, mnt, _ = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if mnt.is_mount(): die(f"vault is open — close it first:  cas {name} close")
    meta = meta_read(img)
    meta.pop("backup_auto", None)
    meta.pop("backup_auto_keep", None)
    meta_strip(img)
    meta_write(img, meta)
    log(f"[✓] auto-backup disabled for '{name}'")
    log(f"    existing auto-backups are kept — delete them manually if needed")

def cmd_backup_auto_keep(name, base, keep):
    img, mnt, _ = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if mnt.is_mount(): die(f"vault is open — close it first:  cas {name} close")
    meta = meta_read(img)
    if not meta.get("backup_auto"):
        die(f"auto-backup is not enabled — run 'cas {name} backup auto enable' first")
    meta["backup_auto_keep"] = keep
    meta_strip(img)
    meta_write(img, meta)
    log(f"[✓] auto-backup keep limit set to {keep} for '{name}'")
    log(f"    excess snapshots will be pruned on the next open")

def cmd_delete(name, base):
    img, mnt, mapper = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if mnt.is_mount(): die(f"vault is open — close it first:  cas {name} close")

    meta = meta_read(img)
    kf_path = resolve_keyfile(meta["keyfile"], meta, img) if "keyfile" in meta else None

    if QUIET or NO_CONFIRM:
        confirm = name
    else:
        log(f"  [!] This will permanently delete '{img}' and all data inside.")
        confirm = ask(f"  Type the vault name '{name}' to confirm")
    if confirm != name: die("aborted")

    img.unlink()
    if kf_path and kf_path.exists():
        kf_path.unlink()
        log(f"  [i] keyfile deleted: {kf_path}")
    try:
        if mnt.exists() and not mnt.is_mount():
            mnt.rmdir()
    except OSError:
        pass
    log(f"[\u2713] vault '{name}' deleted")


def cmd_encryption_toggle(name, base, pw, state):
    """Write encryption=on/off to vault metadata."""
    img, mnt, _ = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if mnt.is_mount():   die(f"vault is open — close it first:  cas {name} close")
    meta = meta_read(img)
    # always derive secret from pw + keyfile (never autokey shortcut) so we verify the real passphrase
    has_2fa = "keyfile" in meta
    if has_2fa:
        kf_path = resolve_keyfile(meta["keyfile"], meta, img)
        secret  = combined_secret(pw, kf_path.read_bytes())
    else:
        secret = pw.encode()
    meta_strip(img)
    if not luks_test(img, secret):
        meta_write(img, meta)
        die("wrong passphrase — could not verify vault")
    if state == "off":
        import base64 as _b64
        meta["encrypted"] = False
        meta["_autokey"]  = _b64.b64encode(secret).decode()
        meta_write(img, meta)
        log(f"[✓] encryption UX disabled — vault will open without prompting for a passphrase")
        log(f"    Note: data is still LUKS-encrypted on disk. This only skips the prompt.")
    else:
        meta.pop("_autokey", None)
        meta.pop("encrypted", None)
        meta_write(img, meta)
        log(f"[✓] encryption UX enabled — passphrase required to open vault")


def parse_size(value_str):
    """Parse a size string like '20 GiB', '512mib', '1tb', '2048' into MiB.
    Case-insensitive. Default unit is MiB if no suffix given."""
    import re
    m = re.fullmatch(r'\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Z]*)\s*', value_str.strip())
    if not m:
        die(f"invalid size '{value_str}' — examples: 2048, 2048M, 2GiB, 1TB")
    num, unit = float(m.group(1)), m.group(2).lower()
    factors = {
        '': 1, 'b': 1/1024/1024,
        'k': 1/1024, 'kb': 1/1024, 'kib': 1/1024,
        'm': 1,      'mb': 1,      'mib': 1,
        'g': 1024,   'gb': 1024,   'gib': 1024,
        't': 1048576,'tb': 1048576,'tib': 1048576,
    }
    if unit not in factors:
        die(f"unknown unit '{unit}' — use K/M/G/T or KiB/MiB/GiB/TiB")
    result = int(num * factors[unit])
    if result < 1:
        die(f"size too small — minimum is 1 MiB")
    return result

def _btrfs_used_mb(mnt):
    """Return used MiB inside a mounted btrfs filesystem, or None on failure."""
    try:
        out = subprocess.check_output(
            ["df", "--block-size=1", "--output=used", str(mnt)],
            stderr=subprocess.DEVNULL).decode().splitlines()
        # output: header line + value line
        return int(out[1].strip()) // (1024 * 1024)
    except Exception:
        pass
    return None

# LUKS2 header overhead in MiB — keep btrfs and cryptsetup well inside the file
_LUKS_OVERHEAD_MB = 32

def cmd_rename(vault, base, args):
    if not args:
        die("missing new name: cas <vault> rename <newname>")

    new = args[-1]

    # prevent same name
    if new == vault:
        die("new name is the same as current name")

    # resolve image
    img, _ = find_img(vault, str(base))

    # ensure closed (check mountpoint)
    import subprocess
    mnt = base / vault
    if subprocess.run(["mountpoint", "-q", str(mnt)]).returncode == 0:
        die(f"vault is open — close it first: cas {vault} close")

    # target path
    new_img = img.with_name(new + ".img")

    # prevent overwrite
    if new_img.exists():
        die(f"target already exists: {new}.img")

    log(f"[cas] renaming '{vault}' -> '{new}' ...")

    img.rename(new_img)

    log(f"[✓] renamed to '{new}'")

def _run_as_user(cmd):
    """Run a command as the real (non-root) user."""
    uid, gid = user_ids()
    def drop():
        os.setgid(gid)
        os.setuid(uid)
    return subprocess.run(cmd, capture_output=True, text=True, check=False, preexec_fn=drop)


def _size_label(mb):
    gb = mb / 1024
    return f"{int(gb)} GB" if gb == int(gb) else f"{gb:.1f} GB"


def _set_btrfs_label(mnt_or_dev, name, mb):
    label = f"{name} [{_size_label(mb)}]"
    subprocess.run(["btrfs", "filesystem", "label", str(mnt_or_dev), label],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _udev_retrigger(dev):
    subprocess.run(["udevadm", "trigger", "--action=change", str(dev)],
                   check=False, stderr=subprocess.DEVNULL)
    subprocess.run(["udevadm", "settle"], check=False, stderr=subprocess.DEVNULL)


def _udisks_loop_setup(img):
    """Register img as a udisks loop device under the real user. Returns loop path or None."""
    import re as _re2
    r = _run_as_user(["udisksctl", "loop-setup", "-f", str(img), "--no-user-interaction"])
    if r.returncode != 0:
        return None
    m = _re2.search(r'(/dev/loop\d+)', r.stdout)
    return m.group(1) if m else None


def _udisks_refresh_size(img):
    """Update udisks loop device size so KDE/Dolphin shows the correct size after resize."""
    # if a persistent loop device already exists, just resize it in-place
    lo = subprocess.run(["losetup", "-j", str(img)], capture_output=True, text=True, check=False)
    for line in lo.stdout.splitlines():
        loop_dev = line.split(":")[0].strip()
        if loop_dev:
            subprocess.run(["losetup", "-c", loop_dev], check=False, stderr=subprocess.DEVNULL)
            subprocess.run(["udevadm", "settle"], check=False, stderr=subprocess.DEVNULL)
            return
    # no existing loop device — cycle one as the real user so udisks/KDE sees it
    loop = _udisks_loop_setup(img)
    if not loop:
        return
    subprocess.run(["udevadm", "settle"], check=False, stderr=subprocess.DEVNULL)
    _run_as_user(["udisksctl", "loop-delete", "-b", loop, "--no-user-interaction"])
    subprocess.run(["udevadm", "settle"], check=False, stderr=subprocess.DEVNULL)


def cmd_resize(name, base, new_mb, pw):
    img, mnt, mapper = resolve(base, name)
    if not img.exists(): die(f"vault '{name}' not found")
    if mnt.is_mount():   die(f"vault is open — close it first:  cas {name} close")

    current_mb = img.stat().st_size // (1024 * 1024)
    shrink = new_mb < current_mb

    if new_mb < _LUKS_OVERHEAD_MB + 64:
        die(f"minimum vault size is {_LUKS_OVERHEAD_MB + 64} MiB")

    meta = meta_read(img)
    secret, meta = get_secret(img, pw, _meta=meta)
    # clean up stale mapper from a previous crashed resize
    subprocess.run(["cryptsetup", "close", mapper], stderr=subprocess.DEVNULL)
    meta_strip(img)
    dev = open_luks(img, mapper, secret)
    mnt.mkdir(exist_ok=True)
    mounted_tmp = False

    # usable MiB inside the LUKS container (LUKS header lives at the start)
    luks_mb = new_mb - _LUKS_OVERHEAD_MB

    # cryptsetup resize requires the volume key on LUKS2
    def cs_resize(sectors=None):
        tf = tmp_keyfile(secret)
        try:
            cmd = ["cryptsetup", "resize", "--key-file", tf, mapper]
            if sectors is not None:
                cmd = ["cryptsetup", "resize", "--key-file", tf,
                       "--size", str(sectors), mapper]
            run(cmd)
        finally:
            os.unlink(tf)

    try:
        if shrink:
            dev_info = subprocess.run(["blkid", dev], stdout=subprocess.PIPE,
                                      stderr=subprocess.DEVNULL).stdout.decode()
            has_fs = "TYPE=" in dev_info

            if has_fs:
                r = subprocess.run(["mount", dev, str(mnt)], stderr=subprocess.PIPE)
                if r.returncode != 0:
                    err = r.stderr.decode().strip()
                    die(f"could not mount vault to check used space\n    {err}")
                mounted_tmp = True

                used_mb = _btrfs_used_mb(mnt)
                if used_mb is not None:
                    min_mb = int(used_mb * 1.10) + 1 + _LUKS_OVERHEAD_MB
                    if new_mb < min_mb:
                        die(f"too small — vault contains ~{used_mb} MiB of data\n"
                            f"    minimum safe size is {min_mb} MiB (110% of used + overhead)\n"
                            f"    try:  cas {name} resize {min_mb}M")
                else:
                    log("  [!] could not read used space — proceeding without safety check")
            else:
                log("  [i] vault has never been opened — no filesystem to check")

            if QUIET or NO_CONFIRM:
                confirm = name
            else:
                log(f"  [!] WARNING: shrinking from {current_mb} to {new_mb} MiB")
                confirm = ask(f"  Type the vault name '{name}' to confirm")
            if confirm != name:
                die("aborted — name did not match")

            log(f"[cas] shrinking '{name}' {current_mb} -> {new_mb} MiB ...")
            if has_fs and mounted_tmp:
                # resize btrfs to the usable space inside the LUKS container
                run(["btrfs", "filesystem", "resize", f"{luks_mb}m", str(mnt)])
                _set_btrfs_label(mnt, name, new_mb)
                run(["umount", str(mnt)])
                mounted_tmp = False
            # resize LUKS container to luks_mb * 512-byte sectors
            cs_resize(sectors=luks_mb * 2048)
            run(["truncate", "-s", f"{new_mb}M", str(img)])
        else:
            if new_mb == current_mb:
                die(f"vault is already {current_mb} MiB")
            log(f"[cas] resizing '{name}' {current_mb} -> {new_mb} MiB ...")
            run(["truncate", "-s", f"{new_mb}M", str(img)])
            cs_resize()

            if mnt.is_mount():
                run(["btrfs", "filesystem", "resize", "max", str(mnt)])
            # btrfs auto-detects the larger device on next mount

        _set_btrfs_label(dev, name, new_mb)
        _udev_retrigger(dev)

    finally:
        if mounted_tmp:
            subprocess.run(["umount", str(mnt)], stderr=subprocess.DEVNULL)
        subprocess.run(["cryptsetup", "close", mapper], stderr=subprocess.DEVNULL)
        try:
            if mnt.exists() and not mnt.is_mount():
                mnt.rmdir()
        except OSError:
            pass

    meta_write(img, meta)
    # force udisks to register the new file size by cycling a loop device
    _udisks_refresh_size(img)
    action_word = "shrunk" if shrink else "resized"
    log(f"[\u2713] '{name}' {action_word} to {new_mb} MiB")

def cmd_list(path_override=None):
    found, seen = [], set()

    # always include open vaults by reading /proc/mounts
    with open("/proc/mounts") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2 and f"{MAPPER_PREFIX}_" in parts[0]:
                mnt  = Path(parts[1])
                img  = mnt.parent / f"{mnt.name}.img"
                if img not in seen and img.exists():
                    seen.add(img)
                    meta    = meta_read(img)
                    size_mb = img.stat().st_size // (1024 * 1024)
                    twofa   = "2fa" if "keyfile" in meta else "   "
                    found.append((img.stem, size_mb, "open  ", twofa, str(img.parent)))

    # also scan for closed vaults in cwd/parents (or path override)
    search = [Path(path_override).resolve()] if path_override \
             else [Path.cwd()] + list(Path.cwd().parents)[:4]
    for d in search:
        for img in sorted(d.glob("*.img")):
            if img in seen: continue
            seen.add(img)
            meta    = meta_read(img)
            size_mb = img.stat().st_size // (1024 * 1024)
            mnt     = img.parent / img.stem
            state   = "open  " if mnt.is_mount() else "closed"
            twofa   = "2fa" if "keyfile" in meta else "   "
            found.append((img.stem, size_mb, state, twofa, str(img.parent)))

    if not found:
        log("[i] no vaults found (searched cwd and 4 levels up)")
        return
    log(f"\n  {'NAME':<20} {'SIZE':>8}   {'STATE':<8}  {'':3}  PATH")
    log(f"  {'-'*20}  {'-'*8}   {'-'*8}  {'-'*3}  {'-'*30}")
    for name, size_mb, state, twofa, path in found:
        log(f"  {name:<20} {size_mb:>7}M   {state:<8}  {twofa:<3}  {path}")
    log()

def cmd_close_all():
    log("[cas] closing all open vaults ...")
    # unmount everything from /proc/mounts that uses an casvault mapper
    with open("/proc/mounts") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2 and f"{MAPPER_PREFIX}_" in parts[0]:
                subprocess.run(["umount", "-l", parts[1]], stderr=subprocess.DEVNULL)
    # close all casvault mappers
    try:
        for d in os.listdir("/dev/mapper"):
            if d.startswith(f"{MAPPER_PREFIX}_"):
                subprocess.run(["cryptsetup", "close", d], stderr=subprocess.DEVNULL)
    except Exception:
        pass
    log("[\u2713] all vaults closed")

# ---------- help ----------

HELP_GLOBAL = """
cas  --  encrypted vault manager
=================================
A vault is a single encrypted file (.img) that works like a folder once opened.
Everything inside is encrypted at rest — only you can read it.

USAGE
  cas <vault> <action> [options]
  cas list
  cas quit
  cas all close
  cas help <action>

ACTIONS (run on a specific vault)
  create    make a new vault
  open      unlock and mount a vault so you can access your files
  close     lock the vault again
  toggle    open if closed, close if open
  info      show vault details (size, open/closed, 2fa status)
  passwd    change the passphrase
  2fa on    generate a keyfile — both passphrase AND keyfile required to open
  2fa off   remove 2FA and delete the keyfile
  encryption on/off  toggle passphrase prompt UX (vault stays encrypted on disk)
  backup    create / list / restore / delete btrfs snapshots inside the vault
  resize    grow or shrink the vault — accepts M/MiB/G/GiB/T/TiB (e.g. 20G, 500MiB)
  delete    permanently delete the vault file
  rename    rename the vault file (must be closed)

GLOBAL
  list      show all vaults found nearby
  all close close every open vault on this machine

OPTIONS
  --pass "..."      passphrase (you will be prompted if not given)
  --keyfile path    path to keyfile (for open if 2FA vault)
  --no-log          suppress all output (for scripts)
  --size MiB        vault size for create  (default: 1024 = 1 GiB)
  --strength level  encryption strength: light / medium / hard / extreme
  --path dir        look for vaults here instead of auto-searching

TYPICAL FIRST USE
  cas myvault create          # create a 1 GiB vault in current folder
  cas myvault open            # open it (prompts for passphrase)
  ...put files in myvault/...
  cas myvault close           # lock it again

Run 'cas help <action>' for details on any command, with examples.
"""

HELP_TOPICS = {
    "create": """
cas <vault> create [--size MiB] [--strength level] [--pass "..."]

Creates a new encrypted vault. The vault is stored as a single file
called <vault>.img in the current directory (or --path).

  --size       How big the vault should be, in MiB.
               Default: 1024  (= 1 GiB). You can resize it later.

  --strength   How hard it is to brute-force your passphrase:
                 light    fastest to unlock, weakest against attacks
                 medium   good for most people  (default)
                 hard     slower to unlock, much stronger
                 extreme  very slow to unlock, very strong
               If in doubt, leave it at medium.

  --pass       Your passphrase. You will be asked if not given here.

EXAMPLES
  cas myvault create
  cas myvault create --size 4096 --strength hard
  cas myvault create --path ~/vaults
""",
    "open": """
cas <vault> open [--pass "..."] [--keyfile path]

Unlocks the vault and makes your files accessible in a folder named
<vault>, next to the .img file.

If 2FA is enabled, you need both your passphrase and keyfile.
The keyfile path is remembered automatically — you only need --keyfile
if the file has moved since last time.

EXAMPLES
  cas myvault open
  cas myvault open --keyfile /mnt/usb/my.key
""",
    "close": """
cas <vault> close

Unmounts and locks the vault. Your files are encrypted again and the
<vault> folder becomes empty. Always close vaults when done.

EXAMPLE
  cas myvault close
""",
    "toggle": """
cas <vault> toggle [--pass "..."]

Opens the vault if it's closed, closes it if it's open.
Great for assigning to a keyboard shortcut or launcher.

EXAMPLE
  cas myvault toggle
""",
    "info": """
cas <vault> info

Shows a summary of the vault:
  - full path and file size
  - whether it is currently open and where
  - whether 2FA is enabled and which keyfile is used
  - number of active LUKS key slots

EXAMPLE
  cas myvault info
""",
    "passwd": """
cas <vault> passwd [--pass "..."] [--new-pass "..."] [--strength level]

Changes the passphrase. The vault must be closed first.
You will be prompted for your current passphrase, then asked for
the new one twice (to avoid typos).

Use --pass and --new-pass for fully non-interactive use (e.g. scripts).
Use --strength to re-key with a different KDF cost (light/medium/hard/extreme).
If --strength is omitted, the new slot inherits default cryptsetup settings.

This is done safely: old slot stays valid until new one is verified.
A crash mid-way cannot lock you out.

If 2FA is enabled, only the passphrase changes — the keyfile stays the same.

EXAMPLE
  cas myvault passwd
  cas myvault passwd --pass "old" --new-pass "new" --no-log
  cas myvault passwd --strength hard
""",
    "2fa": """
cas <vault> 2fa on  [--pass "..."]
cas <vault> 2fa off [--pass "..."]

2FA means the vault needs BOTH a passphrase AND a keyfile to open.

  2fa on
    Generates a keyfile at <vault-dir>/<name>.key (64 random bytes).
    The path is fixed — no choice. Back it up somewhere safe (USB, password
    manager, second machine). If you lose it, the vault cannot be opened.

  2fa off
    Reads the keyfile path from the vault header, disables 2FA, and deletes
    the keyfile. If the keyfile is missing at the cached path, move it back
    there first, then run 'cas <vault> 2fa off' again.

HOW IT WORKS
  The real LUKS passphrase becomes SHA256(your_passphrase + keyfile_contents).
  Neither alone can open the vault.

EXAMPLES
  cas myvault 2fa on
  cas myvault 2fa on --pass "mypassphrase" --no-log
  cas myvault 2fa off
""",
    "backup": """
cas <vault> backup create <name>   — create a readonly btrfs snapshot inside the vault
cas <vault> backup list            — list snapshots (newest first, with creation date)
cas <vault> backup restore <name>  — replace vault contents with a snapshot
cas <vault> backup delete <name>   — delete a snapshot

The vault must be open for all backup operations.
Snapshots live at /.cas-snapshots/<name> inside the vault.

restore asks for confirmation (skipped with --no-log).

EXAMPLES
  cas myvault backup create before-upgrade
  cas myvault backup list
  cas myvault backup restore before-upgrade
  cas myvault backup delete before-upgrade
""",
    "resize": """
cas <vault> resize <size>

Grow or shrink the vault. Size accepts any common unit (case-insensitive):
  20G  20GB  20GiB  20g  — gigabytes
  500M 500MB 500MiB      — megabytes (default if no unit)
  1T   1TB   1TiB        — terabytes
  2048                   — bare number = MiB

  Growing is safe and instant.
  Shrinking is destructive — cas will:
    1. Check that the new size is at least 110% of the data already inside
    2. Ask you to type the vault name to confirm (skipped with --no-log)
    3. Shrink the filesystem, then the LUKS container, then the file

EXAMPLES
  cas myvault resize 2GiB
  cas myvault resize 20 GB
  cas myvault resize 512M
""",
    "delete": """
cas <vault> delete

Permanently deletes the vault file and its keyfile (if 2FA was enabled).
The vault must be closed first.

If the keyfile is missing at the cached path, open the vault first
('cas <vault> open') so the header is verified, then close and delete.

Asks you to type the vault name to confirm. Skipped with --no-log.

EXAMPLE
  cas myvault delete
""",
    "encryption": """
cas <vault> encryption on  [--pass "..."]
cas <vault> encryption off [--pass "..."]

Toggle the passphrase-prompt UX. The vault remains LUKS-encrypted on disk
regardless of this setting — it controls how 'open' behaves.

  encryption off
    Your passphrase (hashed) is stored in the vault's trailing metadata.
    'cas <vault> open' (and toggle) will unlock without prompting.
    Useful if the vault is on a trusted machine and you want seamless access.

  encryption on  (default)
    Removes the stored key from metadata.
    'cas <vault> open' requires your passphrase as normal.

WARNING: 'encryption off' stores your LUKS key derivation material in
plaintext in the vault file's metadata. Only use this if the .img file
itself is on a trusted / already-encrypted volume.

EXAMPLES
  cas myvault encryption off
  cas myvault encryption on
  cas myvault encryption off --pass "mypass" --no-log
""",
    "list": """
cas list [--path dir]

Lists all .img vault files found in the current directory and up to
2 levels up. Shows name, size, open/closed state, and 2FA status.

EXAMPLES
  cas list
  cas list --path ~/vaults
""",
    "all": """
cas all close

Closes every open vault on this machine at once.
Handy before shutting down or handing over your computer.

EXAMPLE
  cas quit
  cas all close
""",
}

def show_help(topic=None):
    if topic and topic in HELP_TOPICS:
        log(HELP_TOPICS[topic])
    elif topic:
        log(f"[x] no help topic '{topic}'")
        log(f"    available: {', '.join(HELP_TOPICS)}")
    else:
        log(HELP_GLOBAL)

# ---------- main ----------

def pop_opt(args, flag, has_value=True):
    if flag not in args:
        return None
    i = args.index(flag)
    args.pop(i)
    if has_value and i < len(args):
        return args.pop(i)
    return True

def get_pw(explicit):
    import sys, shlex

    # 1. explicit --pass
    if explicit:
        log("[!] --pass in shell args is visible in your shell history.")

        # 🔥 smart hint
        try:
            cmd = " ".join(shlex.quote(a) for a in sys.argv)
            hint = cmd.replace(f"--pass {explicit}", "").strip()

            log(f"  [i] use stdin instead:")
            log(f"      printf %s {shlex.quote(explicit)} | {hint}")
        except Exception:
            pass

        from pathlib import Path
        p = Path(explicit)
        if p.exists() and p.is_file():
            return p.read_text().strip()

        return explicit

    # 2. stdin
    if not sys.stdin.isatty():
        data = sys.stdin.read()
        if data:
            return data.rstrip("\n")

    # 3. fallback
    return ask("passphrase", secret=True) or ""

def main():
    global QUIET, NO_CONFIRM
    args = list(sys.argv[1:])
    if "--no-log" in args:
        QUIET = True
        args.remove("--no-log")
    if "--no-confirm" in args:
        NO_CONFIRM = True
        args.remove("--no-confirm")

    if not args or args[0] in ("-h", "--help"):
        show_help(); return

    if args[0] == "help":
        show_help(args[1] if len(args) > 1 else None); return

    opt_pass      = pop_opt(args, "--pass")
    opt_newpass   = pop_opt(args, "--new-pass")
    opt_keyfile   = pop_opt(args, "--keyfile")
    _size_arg     = pop_opt(args, "--size")
    opt_size      = int(_size_arg) if _size_arg else None
    opt_strength  = pop_opt(args, "--strength") or "medium"
    opt_path      = pop_opt(args, "--path")

    if opt_strength not in KDF_PRESETS:
        die(f"unknown strength '{opt_strength}' — choose: light, medium, hard, extreme")

    # cas list
    if args and args[0] == "list":
        cmd_list(opt_path); return

    # cas all close / cas quit
    if len(args) >= 2 and args[0] == "all" and args[1] == "close":
        cmd_close_all(); return
    if len(args) >= 1 and args[0] == "quit":
        cmd_close_all(); return

    # cas path/to/vault.img  (bare path toggle)
    if len(args) == 1 and (args[0].endswith(".img") or os.sep in args[0]):
        p = Path(args[0]).resolve()
        if not p.exists(): die(f"file not found: {p}")
        cmd_toggle(p.stem, p.parent, opt_pass, opt_keyfile); return

    if len(args) < 2:
        show_help(); return

    vault  = args[0]
    action = args[1]
    extra  = args[2:]

    if action == "create":
        base = Path(opt_path or ".").resolve()
        if opt_size is None and not opt_pass:
            size_str = ask("size (e.g. 1G, 500M, 2048)", default="1G")
            opt_size = parse_size(size_str or "1G")
        if opt_pass:
            create_pw = get_pw(opt_pass)
        else:
            create_pw = ask("passphrase (leave empty to generate a strong one)", secret=True) or ""
        cmd_create(vault, base, opt_size, create_pw, opt_strength)

    elif action == "open":
        _, base = find_img(vault, opt_path)
        _img, _ = find_img(vault, opt_path)
        _meta = meta_read(_img)
        effective_kf = opt_keyfile or _meta.get("keyfile")
        with ensure_keyfile_mounted(effective_kf) as kf:
            if _meta.get("encrypted") is False and "_autokey" in _meta:
                cmd_open(vault, base, "", kf)
            else:
                cmd_open(vault, base, get_pw(opt_pass), kf)

    elif action == "rename":
        _, base = find_img(vault, opt_path)
        cmd_rename(vault, base, args)

    elif action == "close":
        _, base = find_img(vault, opt_path)
        cmd_close(vault, base)

    elif action == "toggle":
        _, base = find_img(vault, opt_path)
        with ensure_keyfile_mounted(opt_keyfile) as kf:
            cmd_toggle(vault, base, opt_pass, kf)

    elif action == "info":
        _, base = find_img(vault, opt_path)
        cmd_info(vault, base)

    elif action == "encryption":
        if not extra or extra[0] not in ("on", "off"):
            die("usage: cas <vault> encryption on|off\n    'off' skips passphrase prompt on open (vault stays encrypted on disk)")
        _, base = find_img(vault, opt_path)
        cmd_encryption_toggle(vault, base, get_pw(opt_pass), extra[0])

    elif action == "passwd":
        _, base = find_img(vault, opt_path)
        cmd_passwd(vault, base, get_pw(opt_pass), opt_newpass, opt_strength if opt_strength != "medium" else None)

    elif action == "2fa":
        if not extra or extra[0] not in ("on", "off"):
            die("usage: cas <vault> 2fa on|off\n    Run 'cas help 2fa' for details.")
        _, base = find_img(vault, opt_path)
        pw = get_pw(opt_pass)
        if extra[0] == "on":
            cmd_2fa_on(vault, base, pw)
        else:
            cmd_2fa_off(vault, base, pw)

    elif action == "backup":
        sub = extra[0] if extra else None
        if sub == "create":
            if len(extra) < 2:
                die("usage: cas <vault> backup create <name>\n    Example:  cas myvault backup create before-upgrade")
            _, base = find_img(vault, opt_path)
            cmd_backup_create(vault, base, extra[1])
        elif sub == "list":
            _, base = find_img(vault, opt_path)
            cmd_backup_list(vault, base)
        elif sub == "restore":
            if len(extra) < 2:
                die("usage: cas <vault> backup restore <name>\n    Example:  cas myvault backup restore before-upgrade")
            _, base = find_img(vault, opt_path)
            cmd_backup_restore(vault, base, extra[1])
        elif sub == "delete":
            if len(extra) < 2:
                die("usage: cas <vault> backup delete <name>\n    Example:  cas myvault backup delete old-snap")
            _, base = find_img(vault, opt_path)
            cmd_backup_delete(vault, base, extra[1])
        elif sub == "auto":
            subsub = extra[1] if len(extra) > 1 else None
            if subsub == "enable":
                keep_val = 3
                if len(extra) > 2 and extra[2] == "--keep":
                    if len(extra) < 4 or not extra[3].isdigit():
                        die("usage: cas <vault> backup auto enable [--keep N]")
                    keep_val = int(extra[3])
                    if keep_val < 1:
                        die("--keep must be at least 1")
                _, base = find_img(vault, opt_path)
                cmd_backup_auto_enable(vault, base, keep_val)
            elif subsub == "disable":
                _, base = find_img(vault, opt_path)
                cmd_backup_auto_disable(vault, base)
            elif subsub == "keep":
                if len(extra) < 3 or not extra[2].isdigit():
                    die("usage: cas <vault> backup auto keep <N>\n    Example:  cas myvault backup auto keep 5")
                keep_val = int(extra[2])
                if keep_val < 1:
                    die("keep must be at least 1")
                _, base = find_img(vault, opt_path)
                cmd_backup_auto_keep(vault, base, keep_val)
            else:
                die("usage: cas <vault> backup auto enable [--keep N] | disable | keep <N>")
        else:
            die("usage: cas <vault> backup create|list|restore|delete|auto\n    Run 'cas help backup' for details.")

    elif action == "delete":
        _, base = find_img(vault, opt_path)
        cmd_delete(vault, base)

    elif action in ("resize", "shrink"):
        if not extra:
            die("usage: cas <vault> resize <size>\n    Examples:  cas myvault resize 2048  |  cas myvault resize 20G  |  cas myvault resize 500MiB")
        size_str = extra[0] + (extra[1] if len(extra) > 1 else "")
        _, base = find_img(vault, opt_path)
        cmd_resize(vault, base, parse_size(size_str), get_pw(opt_pass))

    else:
        log(f"[x] unknown action '{action}'")
        log(f"    run 'cas help' to see all commands")
        sys.exit(1)

if __name__ == "__main__":
    main()