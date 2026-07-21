"""
lib/encryption/keyfile.py — Internal keyfile management
Stores keyfile_a and keyfile_b at .img/.cache/encryption/
Used for autorizing internal LUKS operations (add/delete keys).
"""

import os


def _get_keyfile_path(mnt: str, which: str) -> str:
    """Return path to keyfile_a or keyfile_b."""
    if which not in ("a", "b"):
        raise ValueError("which must be 'a' or 'b'")
    return os.path.join(mnt, ".cache", "encryption", f"keyfile_{which}")


def _ensure_cache_dir(mnt: str) -> None:
    """Ensure .cache/encryption directory exists."""
    cache_dir = os.path.join(mnt, ".cache", "encryption")
    os.makedirs(cache_dir, exist_ok=True)


def create_keyfile(mnt: str, which: str) -> bytes:
    """
    Generate and write a new 512-byte keyfile.
    Returns the keyfile bytes.
    which: 'a' or 'b'
    """
    import os as os_module
    _ensure_cache_dir(mnt)
    keyfile_bytes = os_module.urandom(512)
    path = _get_keyfile_path(mnt, which)
    with open(path, "wb") as f:
        f.write(keyfile_bytes)
    # Restrict permissions
    os_module.chmod(path, 0o600)
    return keyfile_bytes


def read_keyfile(mnt: str, which: str) -> bytes:
    """Read keyfile_a or keyfile_b. Returns None if not found."""
    path = _get_keyfile_path(mnt, which)
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "rb") as f:
            return f.read()
    except Exception:
        return None


def keyfile_exists(mnt: str, which: str) -> bool:
    """Check if keyfile exists and is readable."""
    return read_keyfile(mnt, which) is not None


def rotate_keyfile(mnt: str, which: str) -> bytes:
    """
    Rotate a keyfile: create new one, write to keyfile_{a,b}.new.
    Used during refresh auth. Returns the new keyfile bytes.
    """
    import os as os_module
    _ensure_cache_dir(mnt)
    new_bytes = os_module.urandom(512)
    path = _get_keyfile_path(mnt, which)
    new_path = f"{path}.new"
    with open(new_path, "wb") as f:
        f.write(new_bytes)
    os_module.chmod(new_path, 0o600)
    return new_bytes


def promote_new_keyfile(mnt: str, which: str) -> None:
    """Move keyfile_{a,b}.new to keyfile_{a,b}."""
    path = _get_keyfile_path(mnt, which)
    new_path = f"{path}.new"
    if os.path.isfile(new_path):
        os.replace(new_path, path)


def cleanup_new_keyfiles(mnt: str) -> None:
    """Delete any .new keyfiles (used on rollback)."""
    cache_dir = os.path.join(mnt, ".cache", "encryption")
    if os.path.isdir(cache_dir):
        for fname in os.listdir(cache_dir):
            if fname.endswith(".new"):
                try:
                    os.remove(os.path.join(cache_dir, fname))
                except Exception:
                    pass
