"""
core/parser/processing/defaults.py — loads and applies blueprint defaults
"""

import os
import json
import copy

from common.io.strip import jsonc as strip_jsonc


def load_defaults(path: str = None) -> dict:
    if path is None:
        from common.config import get_config_path
        path = get_config_path("defaults")
    with open(path, "r", encoding="utf-8") as f:
        return json.loads(strip_jsonc(f.read()))


def apply_defaults(section: str, data: dict, defaults: dict) -> tuple[dict, list[str]]:
    if section not in defaults:
        return data, []

    schema   = defaults[section]
    defs     = schema.get("defaults", {})
    required = schema.get("required", [])
    errors   = []

    merged = copy.deepcopy(defs)
    merged.update(data)

    for field in required:
        if not merged.get(field):
            errors.append(f"[{section}] missing required field: {field}")

    return merged, errors