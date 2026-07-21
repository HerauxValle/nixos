"""
lib/encryption/derive.py — Host-derived key generation
Fingerprints the host and derives a LUKS passphrase via Argon2id + HKDF.
"""

import os
import hashlib
import subprocess
from typing import Optional

from common.emit import emit


def _get_derived_salt_path(mnt: str) -> str:
    """Return path to derived_salt file."""
    return os.path.join(mnt, ".cache", "encryption", "derived_salt")


def _read_or_create_salt(mnt: str) -> bytes:
    """Read existing salt or create new 32-byte salt."""
    salt_path = _get_derived_salt_path(mnt)
    if os.path.isfile(salt_path):
        try:
            with open(salt_path, "rb") as f:
                salt = f.read()
                if len(salt) == 32:
                    return salt
        except Exception:
            pass

    # Create new salt
    os.makedirs(os.path.dirname(salt_path), exist_ok=True)
    salt = os.urandom(32)
    try:
        with open(salt_path, "wb") as f:
            f.write(salt)
        os.chmod(salt_path, 0o600)
    except Exception:
        emit("warning", "could not write derived_salt to cache")
    return salt


def _collect_fingerprint_sources() -> dict:
    """Collect all available host fingerprint sources."""
    sources = {}

    # 1. machine-id
    try:
        with open("/etc/machine-id", "r") as f:
            sources["machine-id"] = f.read().strip()
    except Exception:
        pass

    # 2. motherboard UUID (via dmidecode)
    try:
        result = subprocess.run(
            ["sudo", "dmidecode", "-s", "system-uuid"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            uuid_str = result.stdout.strip()
            if uuid_str and uuid_str.lower() != "not specified":
                sources["motherboard-uuid"] = uuid_str
    except Exception:
        pass

    # 3. primary MAC address
    try:
        import uuid
        mac = uuid.getnode()
        if mac != (1 << 48) - 1:  # not a fake multicast MAC
            sources["mac"] = format(mac, '012x')
    except Exception:
        pass

    # 4. root fs UUID
    try:
        result = subprocess.run(
            ["sudo", "blkid", "-s", "UUID", "-o", "value", "/"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            uuid_str = result.stdout.strip()
            if uuid_str:
                sources["root-fs-uuid"] = uuid_str
    except Exception:
        pass

    # 5. CPU model string
    try:
        with open("/proc/cpuinfo", "r") as f:
            for line in f:
                if line.startswith("model name"):
                    sources["cpu-model"] = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass

    return sources


def _build_fingerprint(sources: dict) -> str:
    """Build deterministic fingerprint from collected sources."""
    # Sort keys for determinism
    sorted_keys = sorted(sources.keys())
    parts = [sources[k] for k in sorted_keys]
    concat = "|".join(parts)
    return hashlib.sha256(concat.encode()).hexdigest()


def _hkdf_extract(salt: bytes, ikm: bytes) -> bytes:
    """HKDF-Extract (RFC 5869) using HMAC-SHA256."""
    import hmac
    return hmac.new(salt, ikm, hashlib.sha256).digest()


def _hkdf_expand(prk: bytes, info: bytes, length: int) -> bytes:
    """HKDF-Expand (RFC 5869) using HMAC-SHA256."""
    import hmac
    import math
    n = math.ceil(length / 32)
    okm = b""
    t = b""
    for i in range(1, n + 1):
        t = hmac.new(prk, t + info + bytes([i]), hashlib.sha256).digest()
        okm += t
    return okm[:length]


def derive_passphrase(mnt: str, preset) -> str:
    """
    Derive the host passphrase using Argon2id (CLI) + HKDF (stdlib).
    preset: lib.encryption.presets.Preset object
    Returns: 32-byte LUKS passphrase (hex string for compatibility)
    """
    sources = _collect_fingerprint_sources()
    if not sources:
        from common.errors import error
        error("NO_FINGERPRINT", "could not collect any host fingerprint sources")

    fingerprint = _build_fingerprint(sources)
    salt = _read_or_create_salt(mnt)

    # Argon2id via system CLI (no pip deps)
    import base64
    salt_b64 = base64.b64encode(salt[:16]).decode()
    mem_kib = preset.argon2_memory // 1024
    result = subprocess.run(
        ["argon2", salt_b64, "-id",
         "-t", str(preset.argon2_time),
         "-k", str(mem_kib),
         "-p", str(preset.argon2_parallel),
         "-l", "64", "-r"],
        input=fingerprint, capture_output=True, text=True, timeout=120
    )
    if result.returncode != 0:
        from common.errors import error
        error("DERIVE_FAILED", "argon2 CLI failed", result.stderr.strip())

    argon_bytes = bytes.fromhex(result.stdout.strip())

    # HKDF-SHA256 (stdlib only)
    prk = _hkdf_extract(salt, argon_bytes)
    final_key = _hkdf_expand(prk, b"simpledocker+/luks/derived/v1", 32)

    return final_key.hex()


def get_or_derive_passphrase(mnt: str, preset) -> str:
    """Wrapper that always derives the key (same sources, same salt = same result)."""
    return derive_passphrase(mnt, preset)
