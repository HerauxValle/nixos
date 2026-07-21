"""
core/settings.py — user rule resolution and persistence
Resolution order: .cache/settings.json → img config/rules.jsonc → project config/rules.jsonc
"""

import os
import json

from common.io.strip import jsonc as strip_jsonc

# known rules with their valid values (None = any value accepted)
RULES: dict[str, list | None] = {
    "DEFAULT_MODE":  ["table", "verbose"],
    "TABLE_DISPLAY": ["simple", "responsive"],
    "TABLE_SIZE":    ["auto", "max"],
    "TABLES_CACHED":     None,   # int
    "ENABLE_DAEMON":     [True, False, "true", "false"],
    "IMPORT_BLUEPRINTS": None,   # str — path or ""
    "encryption_default_preset": ["light", "medium", "strong", "extreme"],  # default KDF params
}

_CACHE_FILE  = ".cache/settings.json"
_RULES_FILE  = "config/rules.jsonc"  # relative to mnt or project root

# module-level cache — loaded once per process, invalidated on set/unset
_cache: dict | None = None


def _mnt() -> str | None:
    try:
        from common.session import SESSIONS_BASE, _session_key
        path = os.path.join(SESSIONS_BASE, _session_key())
        if not os.path.isfile(path):
            return None
        mnt = open(path).read().strip()
        return mnt if os.path.isdir(mnt) else None
    except Exception:
        return None


def _load_defaults() -> dict:
    """Load rules.jsonc — img first, project fallback. Never raises."""
    def _read(path: str) -> dict:
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.loads(strip_jsonc(f.read()))
        except Exception:
            return {}

    img_rules = {}
    # try img config only if a session actually exists
    try:
        import os as _os
        from common.session import SESSIONS_BASE, _session_key
        session_file = _os.path.join(SESSIONS_BASE, _session_key())
        if _os.isfile(session_file):
            mnt = open(session_file).read().strip()
            if _os.path.isdir(mnt):
                from common.shebang import scan_dir
                found = scan_dir(_os.path.join(mnt, "config"))
                if "rules" in found:
                    img_rules = _read(found["rules"])
    except Exception:
        pass

    # project config — always check, especially for IMPORT_BLUEPRINTS
    from common.config import PROJECT_CONFIG
    from common.shebang import scan_dir
    found = scan_dir(PROJECT_CONFIG)
    project_rules = {}
    if "rules" in found:
        project_rules = _read(found["rules"])

    # merge: img first, then layer in project (project wins for IMPORT_BLUEPRINTS)
    result = {**img_rules, **project_rules}
    return result


def _load_overrides(mnt: str) -> dict:
    """Load .cache/settings.json from img. Returns {} if missing."""
    path = os.path.join(mnt, _CACHE_FILE)
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _save_overrides(mnt: str, overrides: dict) -> None:
    path = os.path.join(mnt, _CACHE_FILE)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(overrides, f, indent=2)


def _coerce(key: str, value: str) -> object:
    """Coerce string value to correct type for key."""
    if key == "TABLES_CACHED":
        return int(value)
    if key == "ENABLE_DAEMON":
        return value.lower() in ("true", "1", "yes", "on") if isinstance(value, str) else bool(value)
    return value


def _validate(key: str, value: object) -> None:
    from common.errors import error
    if key not in RULES:
        error("UNKNOWN_RULE", f"unknown rule '{key}'",
              f"valid: {', '.join(RULES.keys())}")
    valid = RULES[key]
    if valid is None:
        return
    coerced = _coerce(key, str(value)) if isinstance(value, str) else value
    if coerced not in valid and str(coerced).lower() not in [str(v).lower() for v in valid]:
        error("INVALID_VALUE", f"invalid value '{value}' for rule '{key}'",
              f"valid: {', '.join(str(v) for v in valid)}")


def get_rule(key: str) -> object:
    """Get a rule value. Uses module cache for performance."""
    global _cache
    if _cache is None:
        defaults  = _load_defaults()
        mnt       = _mnt()
        overrides = _load_overrides(mnt) if mnt else {}
        _cache    = {**defaults, **overrides}
    return _cache.get(key)


def set_rule(key: str, value: str) -> None:
    global _cache
    _validate(key, value)
    mnt = _mnt()
    if not mnt:
        from common.errors import error
        error("NO_SESSION", "no active img — select one first")
    overrides       = _load_overrides(mnt)
    overrides[key]  = _coerce(key, value)
    _save_overrides(mnt, overrides)
    _cache = None   # invalidate


def unset_rule(key: str) -> None:
    global _cache
    if key not in RULES:
        from common.errors import error
        error("UNKNOWN_RULE", f"unknown rule '{key}'",
              f"valid: {', '.join(RULES.keys())}")
    mnt = _mnt()
    if not mnt:
        from common.errors import error
        error("NO_SESSION", "no active img — select one first")
    overrides = _load_overrides(mnt)
    if key not in overrides:
        from common.errors import error
        error("RULE_NOT_SET", f"rule '{key}' is not overridden",
              "nothing to unset — it already uses the default")
    del overrides[key]
    _save_overrides(mnt, overrides)
    _cache = None   # invalidate


def get_external_blueprints_dir() -> str | None:
    """
    Return the resolved external blueprints directory from IMPORT_BLUEPRINTS rule.
    Returns None if the rule is empty, unset, or the directory doesn't exist.
    Relative paths are resolved against PROJECT_ROOT.
    """
    val = get_rule("IMPORT_BLUEPRINTS")
    if not val or not str(val).strip():
        return None
    path = str(val).strip()
    if not os.path.isabs(path):
        from lib.variables.general import PROJECT_ROOT
        path = os.path.join(PROJECT_ROOT, path)
    return path if os.path.isdir(path) else None


def list_rules() -> list[dict]:
    """Return all rules with source (default/override) for display."""
    defaults  = _load_defaults()
    mnt       = _mnt()
    overrides = _load_overrides(mnt) if mnt else {}
    rows = []
    for key in RULES:
        override = key in overrides
        rows.append({
            "rule":    key,
            "value":   str(overrides.get(key, defaults.get(key, ""))),
            "source":  "override" if override else "default",
        })
    return rows