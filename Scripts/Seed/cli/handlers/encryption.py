"""cli/handlers/encryption.py — public encryption command handlers"""
import os
from common.emit import emit
from common.errors import error
from lib.encryption.presets import (load_preset, list_presets,
    create_preset as preset_create, delete_preset as preset_delete)
from lib.encryption.slots import (find_free_slot, add_slot, remove_slot,
    rename_slot as slot_rename, get_slot_by_number, list_all_slots, list_slots_by_type)
from lib.encryption.keyfile import read_keyfile
from lib.encryption.derive import get_or_derive_passphrase
from lib.encryption.luks import add_key as luks_add_key, delete_key as luks_delete_key, dump
from lib.encryption.guard import (check_safe_to_remove_slot, check_safe_to_add_slot,
    check_safe_to_enable, check_safe_to_refresh_auth)
from lib.variables.general import SLOT_HARDCODED, LUKS_DEFAULT_KEY
from cli.handlers._enc_helpers import (_get_enc_mnt, _resolve_preset, _resolve_slot,
    _get_img_path, _try_auth_add, _try_auth_delete)

def _enc_create_handler(a):
    if a.arg1 == "preset":
        create_preset(a.arg2 or "", a)
    else:
        error("UNKNOWN_TARGET", f"unknown create target '{a.arg1}'", "valid: preset")

def _enc_add_handler(a):
    if a.arg1 == "key":
        add_key(a.arg2 or "", a.preset or "", getattr(a, 'name', None))
    else:
        error("UNKNOWN_TARGET", f"unknown add target '{a.arg1}'", "valid: key")

def _enc_delete_handler(a):
    if a.arg1 == "key":
        delete_key(a.arg2 or "")
    elif a.arg1 == "preset":
        delete_preset(a.arg2 or "")
    else:
        error("UNKNOWN_TARGET", f"unknown delete target '{a.arg1}'", "valid: key, preset")

def _enc_list_handler(a):
    if a.arg1 == "slots":       list_slots()
    elif a.arg1 == "verified":  list_verified()
    elif a.arg1 == "all":       list_all_user_slots()
    else: error("UNKNOWN_TARGET", f"unknown list target '{a.arg1}'", "valid: slots, verified, all")

def _enc_refresh_handler(a):
    if a.arg1 == "auth": refresh_auth()
    else: error("UNKNOWN_TARGET", f"unknown refresh target '{a.arg1}'", "valid: auth")


# ── Key management ───────────────────────────────────────────────────────────

def add_key(password: str, preset_name: str = "", name: str = None) -> None:
    mnt = _get_enc_mnt(); img_path = _get_img_path()
    preset = _resolve_preset(preset_name, mnt)
    check_safe_to_add_slot(mnt)
    slot_num = find_free_slot(mnt)
    if slot_num is None: error("NO_FREE_SLOTS", "all user slots are full")
    if not _try_auth_add(img_path, slot_num, password, preset, mnt):
        error("ADD_KEY_FAILED", "failed to add key to LUKS")
    add_slot(mnt, slot_num, "passkey", name, preset.name)
    emit("action", "added", f"passkey at slot {slot_num}" + (f" ({name})" if name else ""))

def delete_key(slot_or_name: str) -> None:
    mnt = _get_enc_mnt(); img_path = _get_img_path()
    slot_num = _resolve_slot(slot_or_name, mnt)
    check_safe_to_remove_slot(mnt, img_path)
    if not _try_auth_delete(img_path, slot_num, mnt):
        error("DELETE_KEY_FAILED", "failed to remove key from LUKS")
    remove_slot(mnt, slot_num)
    emit("action", "deleted", f"passkey at slot {slot_num}")


# ── Preset management ────────────────────────────────────────────────────────

def create_preset(name: str, args) -> None:
    mnt = _get_enc_mnt()
    memory = getattr(args, "argon2_memory", None)
    time_ = getattr(args, "argon2_time", None)
    parallel = getattr(args, "argon2_parallel", None)
    if memory is None or time_ is None or parallel is None:
        error("MISSING_PARAMS", "preset requires -argon2-memory, -argon2-time, -argon2-parallel")
    mem, t, p = int(memory), int(time_), int(parallel)
    issues = []
    if t < 4:    issues.append(f"iterations={t} < 4 (cryptsetup minimum)")
    if mem < 8192: issues.append(f"memory={mem} < 8192 bytes (8KiB minimum)")
    if p < 1:    issues.append(f"parallelism={p} < 1")
    if issues:   error("INVALID_PRESET", "; ".join(issues))
    preset_create(name, "argon2id", mem, t, p, mnt)
    emit("action", "created", f"preset '{name}'")

def delete_preset(name: str) -> None:
    mnt = _get_enc_mnt()
    preset_delete(name, mnt)
    emit("action", "deleted", f"preset '{name}'")

def validate_preset(name: str = "", all_: bool = False) -> None:
    mnt = _get_enc_mnt()
    if all_ and not name:     targets = list_presets(mnt)
    elif name:
        p = load_preset(name, mnt)
        if not p: error("NOT_FOUND", f"preset '{name}' not found")
        targets = [p]
    else: error("MISSING_ARG", "preset name required or use -all flag"); return
    rows = []
    for p in targets:
        status, issues = "✓", []
        if p.pbkdf == "argon2id":
            if p.argon2_time < 4:      status = "✗"; issues.append(f"iterations {p.argon2_time} < 4")
            if p.argon2_memory < 8192: status = "✗"; issues.append(f"memory {p.argon2_memory} < 8KiB")
            if p.argon2_parallel and p.argon2_parallel < 1: status = "✗"; issues.append(f"parallelism < 1")
        rows.append({"name": p.name, "kdf": p.pbkdf, "status": status,
                     "issues": " | ".join(issues) if issues else "—"})
    emit("table", rows) if rows else emit("action", "presets", "none")


# ── Listing ──────────────────────────────────────────────────────────────────

def list_slots() -> None:
    mnt = _get_enc_mnt()
    slots = list_slots_by_type(mnt, "passkey")
    if not slots: emit("action", "encryption", "no passkey slots found"); return
    rows = [{"slot": str(s), "type": "passkey", "name": m.get("name") or "—", "preset": m.get("preset", "?")}
            for s, m in slots]
    emit("table", rows, type="flat")

def list_verified() -> None:
    mnt = _get_enc_mnt()
    slots = list_slots_by_type(mnt, "verified")
    if not slots: emit("action", "encryption", "no verified systems found"); return
    rows = [{"slot": str(s), "type": "verified", "name": m.get("name") or "—", "preset": m.get("preset", "?")}
            for s, m in slots]
    emit("table", rows, type="flat")

def list_all_user_slots() -> None:
    mnt = _get_enc_mnt()
    sl = list_all_slots(mnt)
    if not sl: emit("action", "encryption", "no user slots found"); return
    rows = [{"slot": str(s), "type": m.get("type", "?"), "name": m.get("name") or "—", "preset": m.get("preset", "?")}
            for s, m in sl]
    emit("table", rows, type="flat")


# ── Verify / unverify ────────────────────────────────────────────────────────

def verify_host(name: str = None) -> None:
    mnt = _get_enc_mnt(); img_path = _get_img_path()
    preset = _resolve_preset("", mnt)
    check_safe_to_add_slot(mnt)
    slot_num = find_free_slot(mnt)
    if slot_num is None: error("NO_FREE_SLOTS", "all user slots are full")
    derived_key = get_or_derive_passphrase(mnt, preset)
    if not _try_auth_add(img_path, slot_num, derived_key, preset, mnt):
        error("ADD_KEY_FAILED", "failed to add derived key to LUKS")
    add_slot(mnt, slot_num, "verified", name, preset.name)
    emit("action", "verified", f"host at slot {slot_num}" + (f" ({name})" if name else ""))

def unverify_host(slot_or_name: str) -> None:
    mnt = _get_enc_mnt(); img_path = _get_img_path()
    slot_num = _resolve_slot(slot_or_name, mnt)
    metadata = get_slot_by_number(mnt, slot_num)
    if not metadata or metadata.get("type") != "verified":
        error("NOT_VERIFIED", f"slot {slot_num} is not a verified system")
    check_safe_to_remove_slot(mnt, img_path)
    if not _try_auth_delete(img_path, slot_num, mnt):
        error("DELETE_KEY_FAILED", "failed to remove verified key from LUKS")
    remove_slot(mnt, slot_num)
    emit("action", "unverified", f"slot {slot_num}")

def rename_slot(slot_or_name: str, new_name: str) -> None:
    mnt = _get_enc_mnt()
    slot_num = _resolve_slot(slot_or_name, mnt)
    slot_rename(mnt, slot_num, new_name)
    emit("action", "renamed", f"slot {slot_num} → {new_name}")


# ── Keyfile rotation ─────────────────────────────────────────────────────────

def refresh_auth() -> None:
    from lib.variables.general import SLOT_KEYFILE_A, SLOT_KEYFILE_B
    from lib.encryption.keyfile import rotate_keyfile, promote_new_keyfile, cleanup_new_keyfiles
    import tempfile
    mnt = _get_enc_mnt(); img_path = _get_img_path()
    check_safe_to_refresh_auth(mnt, img_path)
    old_a, old_b = read_keyfile(mnt, "a"), read_keyfile(mnt, "b")
    if not old_a or not old_b: error("NO_KEYFILES", "both keyfile_a and keyfile_b must exist")
    try:
        new_a, new_b = rotate_keyfile(mnt, "a"), rotate_keyfile(mnt, "b")
        with tempfile.NamedTemporaryFile(delete=False) as f: f.write(old_b); old_b_path = f.name
        try:
            if not luks_delete_key(img_path, SLOT_KEYFILE_A, auth_keyfile=old_b_path):
                cleanup_new_keyfiles(mnt); error("REFRESH_FAILED", "remove old keyfile_a failed")
            with tempfile.NamedTemporaryFile(delete=False) as f: f.write(new_a); new_a_path = f.name
            try:
                if not luks_add_key(img_path, SLOT_KEYFILE_A, auth_keyfile=old_b_path, new_keyfile=new_a_path):
                    cleanup_new_keyfiles(mnt); error("REFRESH_FAILED", "add new keyfile_a failed")
            finally: os.remove(new_a_path)
            with tempfile.NamedTemporaryFile(delete=False) as f: f.write(new_a); new_a_auth = f.name
            try:
                if not luks_delete_key(img_path, SLOT_KEYFILE_B, auth_keyfile=new_a_auth):
                    cleanup_new_keyfiles(mnt); error("REFRESH_FAILED", "remove old keyfile_b failed")
                with tempfile.NamedTemporaryFile(delete=False) as f: f.write(new_b); new_b_path = f.name
                try:
                    if not luks_add_key(img_path, SLOT_KEYFILE_B, auth_keyfile=new_a_auth, new_keyfile=new_b_path):
                        cleanup_new_keyfiles(mnt); error("REFRESH_FAILED", "add new keyfile_b failed")
                finally: os.remove(new_b_path)
            finally: os.remove(new_a_auth)
            promote_new_keyfile(mnt, "a"); promote_new_keyfile(mnt, "b")
            emit("action", "refreshed", "internal keyfiles rotated")
        finally: os.remove(old_b_path)
    except Exception: cleanup_new_keyfiles(mnt); raise


# ── Enable / disable ─────────────────────────────────────────────────────────

def enable_encryption() -> None:
    mnt = _get_enc_mnt(); img_path = _get_img_path()
    luks_state = dump(img_path)
    if luks_state and SLOT_HARDCODED not in luks_state.get("active_slots", []):
        emit("action", "encryption", "already enabled"); return
    check_safe_to_enable(mnt)
    keyfile_a = read_keyfile(mnt, "a")
    if not keyfile_a: error("NO_KEYFILE_A", "internal keyfile_a missing")
    import tempfile
    with tempfile.NamedTemporaryFile(delete=False) as f: f.write(keyfile_a); tmp = f.name
    try:
        if not luks_delete_key(img_path, SLOT_HARDCODED, auth_keyfile=tmp):
            error("ENABLE_FAILED", "failed to remove hardcoded passkey")
        emit("action", "enabled", "encryption (hardcoded key removed)")
    finally: os.remove(tmp)

def disable_encryption() -> None:
    import tempfile
    mnt = _get_enc_mnt(); img_path = _get_img_path()
    luks_state = dump(img_path)
    if luks_state and SLOT_HARDCODED in luks_state.get("active_slots", []):
        emit("action", "encryption", "already disabled"); return
    keyfile_a = read_keyfile(mnt, "a")
    if not keyfile_a: error("NO_KEYFILE_A", "internal keyfile_a missing")
    light_preset = load_preset("light", mnt)
    if not light_preset: error("PRESET_ERROR", "light preset not available")
    with tempfile.NamedTemporaryFile(delete=False) as f: f.write(keyfile_a); tmp = f.name
    try:
        if not luks_add_key(img_path, SLOT_HARDCODED, LUKS_DEFAULT_KEY, auth_keyfile=tmp, preset=light_preset):
            error("DISABLE_FAILED", "failed to restore hardcoded passkey")
        emit("action", "disabled", "encryption (hardcoded key restored)")
    finally: os.remove(tmp)
