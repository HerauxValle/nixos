"""
lib/encryption/presets.py — KDF preset management
Built-in presets loaded from config/encryption-presets.jsonc
Custom user presets stored in .img/config/ with shebang #!sd-encryption-preset
"""

import os
import json
from dataclasses import dataclass
from typing import Optional

from common.emit import emit
from common.io.strip import jsonc as strip_jsonc


@dataclass
class Preset:
    name: str
    builtin: bool
    pbkdf: str
    argon2_memory: int      # in bytes
    argon2_time: int        # iterations
    argon2_parallel: Optional[int]    # parallelism (None = use core count)


def _load_builtin_presets(mnt: str = None) -> dict:
    """
    Load built-in presets from config/encryption-presets.jsonc.
    Checks .img/config first (if mnt provided), then falls back to PROJECT_CONFIG.
    """
    from lib.variables.general import PROJECT_CONFIG
    from common.shebang import find

    # Try .img/config first if mounted
    preset_file = None
    if mnt:
        img_config = os.path.join(mnt, "config")
        if os.path.isdir(img_config):
            preset_file = find("encryption-presets", img_config)

    # Fall back to project config
    if not preset_file:
        preset_file = find("encryption-presets", PROJECT_CONFIG)

    if not preset_file:
        return {}

    try:
        with open(preset_file, "r") as f:
            data = json.loads(strip_jsonc(f.read()))

        result = {}
        for name, preset_data in data.items():
            # Handle extreme preset's parallel = None → use core count
            parallel = preset_data.get("argon2-parallel")
            if parallel is None and name == "extreme":
                try:
                    import multiprocessing
                    parallel = multiprocessing.cpu_count()
                except Exception:
                    parallel = 4

            result[name] = Preset(
                name=name,
                builtin=preset_data.get("builtin", True),
                pbkdf=preset_data.get("pbkdf", "argon2id"),
                argon2_memory=preset_data.get("argon2-memory", 0),
                argon2_time=preset_data.get("argon2-time", 0),
                argon2_parallel=parallel,
            )
        return result
    except Exception:
        emit("warning", "could not load encryption presets from config")
        return {}


_BUILTIN_PRESETS_CACHE = None

def _get_builtin_presets(mnt: str = None) -> dict:
    """Load built-in presets. With mnt, checks .img/config first."""
    global _BUILTIN_PRESETS_CACHE
    # Only cache when no mnt specified (project config only)
    if mnt is None:
        if _BUILTIN_PRESETS_CACHE is None:
            _BUILTIN_PRESETS_CACHE = _load_builtin_presets(mnt)
        return _BUILTIN_PRESETS_CACHE
    # If mnt specified, always load (might be different per img)
    return _load_builtin_presets(mnt)


def _get_presets_dir(mnt: str) -> str:
    """Return path to config directory where presets live."""
    return os.path.join(mnt, "config")


def _ensure_encryption_cache(mnt: str) -> str:
    """Ensure .cache/encryption directory exists. Return path."""
    cache_dir = os.path.join(mnt, ".cache", "encryption")
    os.makedirs(cache_dir, exist_ok=True)
    return cache_dir


def load_preset(name: str, mnt: str) -> Optional[Preset]:
    """
    Load a preset by name. Checks built-in first, then disk.
    Returns None if not found.
    """
    builtin = _get_builtin_presets()
    if name in builtin:
        return builtin[name]

    # Try to load from disk
    presets_dir = _get_presets_dir(mnt)
    if not os.path.isdir(presets_dir):
        return None

    for filename in os.listdir(presets_dir):
        filepath = os.path.join(presets_dir, filename)
        if not os.path.isfile(filepath):
            continue
        try:
            with open(filepath, "r") as f:
                first_line = f.readline().strip()
                if first_line != "#!sd-encryption-preset":
                    continue
                # Re-read file and parse JSON (skip first line)
                f.seek(0)
                f.readline()  # skip shebang
                data = json.load(f)
                if data.get("name") == name:
                    return Preset(
                        name=data["name"],
                        builtin=False,
                        pbkdf=data["pbkdf"],
                        argon2_memory=data["argon2-memory"],
                        argon2_time=data["argon2-time"],
                        argon2_parallel=data["argon2-parallel"],
                    )
        except Exception:
            continue

    return None


def list_presets(mnt: str) -> list[Preset]:
    """List all available presets (built-in + disk)."""
    result = list(_get_builtin_presets().values())

    presets_dir = _get_presets_dir(mnt)
    if not os.path.isdir(presets_dir):
        return result

    seen = {p.name for p in result}
    for filename in os.listdir(presets_dir):
        filepath = os.path.join(presets_dir, filename)
        if not os.path.isfile(filepath):
            continue
        try:
            with open(filepath, "r") as f:
                first_line = f.readline().strip()
                if first_line != "#!sd-encryption-preset":
                    continue
                f.seek(0)
                f.readline()
                data = json.load(f)
                name = data.get("name")
                if name and name not in seen:
                    result.append(Preset(
                        name=name,
                        builtin=False,
                        pbkdf=data["pbkdf"],
                        argon2_memory=data["argon2-memory"],
                        argon2_time=data["argon2-time"],
                        argon2_parallel=data["argon2-parallel"],
                    ))
                    seen.add(name)
        except Exception:
            continue

    return result


def create_preset(name: str, pbkdf: str, argon2_memory: int, argon2_time: int, argon2_parallel: int, mnt: str) -> None:
    """
    Create a custom preset. Raises error if name matches built-in.
    Writes to .img/config/ with shebang.
    """
    builtin = _get_builtin_presets()
    if name in builtin:
        from common.errors import error
        error("BUILTIN_PRESET", f"cannot override built-in preset '{name}'")

    from common.sanitize import safe_name
    safe_name(name, "preset")
    presets_dir = _get_presets_dir(mnt)
    os.makedirs(presets_dir, exist_ok=True)

    # Find first available filename
    filename = f"{name}.json"
    i = 1
    filepath = os.path.join(presets_dir, filename)
    while os.path.exists(filepath):
        filename = f"{name}_{i}.json"
        filepath = os.path.join(presets_dir, filename)
        i += 1

    data = {
        "name": name,
        "builtin": False,
        "pbkdf": pbkdf,
        "argon2-memory": argon2_memory,
        "argon2-time": argon2_time,
        "argon2-parallel": argon2_parallel,
    }

    with open(filepath, "w") as f:
        f.write("#!sd-encryption-preset\n")
        json.dump(data, f, indent=2)


def delete_preset(name: str, mnt: str) -> None:
    """
    Delete a custom preset. Raises error if name is built-in.
    """
    builtin = _get_builtin_presets()
    if name in builtin:
        from common.errors import error
        error("BUILTIN_PRESET", f"cannot delete built-in preset '{name}'")

    presets_dir = _get_presets_dir(mnt)
    if not os.path.isdir(presets_dir):
        from common.errors import error
        error("NOT_FOUND", f"preset '{name}' not found")

    found = False
    for filename in os.listdir(presets_dir):
        filepath = os.path.join(presets_dir, filename)
        if not os.path.isfile(filepath):
            continue
        try:
            with open(filepath, "r") as f:
                first_line = f.readline().strip()
                if first_line != "#!sd-encryption-preset":
                    continue
                f.seek(0)
                f.readline()
                data = json.load(f)
                if data.get("name") == name:
                    os.remove(filepath)
                    found = True
                    break
        except Exception:
            continue

    if not found:
        from common.errors import error
        error("NOT_FOUND", f"preset '{name}' not found")
