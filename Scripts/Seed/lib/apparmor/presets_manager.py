"""
lib/apparmor/presets_manager.py — Preset lookup and validation.
"""

from common.errors import error


def get_preset(name: str) -> dict:
    """Get preset rules by name.

    Validates preset exists.

    Args:
        name: Preset name (strict|default|permissive)

    Returns:
        Dict with preset configuration

    Raises:
        error() if preset not found
    """
    from lib.apparmor.presets import strict, default, permissive

    presets = {
        "strict": strict.STRICT,
        "default": default.DEFAULT,
        "permissive": permissive.PERMISSIVE,
    }

    if name not in presets:
        error(
            "INVALID_PRESET",
            f"Unknown preset: {name}",
            f"Valid: {', '.join(presets.keys())}",
        )

    return presets[name]
