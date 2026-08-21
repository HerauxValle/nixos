"""
cli/completion.py — Handle ... fuzzy matching for container/blueprint names
Integrates into command processing to expand patterns like "sd stop n8n..."
"""

from lib.fuzzy import fuzzy_match


def _get_available_items(cmd: str, mnt: str) -> list[str]:
    """Get list of available items for a command (containers, blueprints, etc)."""
    import os

    # Map commands to what they operate on
    item_map = {
        # Container operations
        "stop": "containers",
        "logs": "containers",
        "exec": "containers",
        "restart": "containers",
        # Image/blueprint operations
        "close": "images",
        "run": "blueprints",
        "edit": "names",  # blueprints/formats (flexible)
        "validate": "blueprints",
        "delete": "names",  # containers/blueprints (flexible)
    }

    item_type = item_map.get(cmd)
    if not item_type:
        return []

    if item_type == "containers":
        cdir = os.path.join(mnt, "containers")
        if os.path.isdir(cdir):
            return sorted(os.listdir(cdir))
    elif item_type == "images":
        # Get mounted images
        try:
            from common.session import list_active_images
            return list_active_images()
        except Exception:
            return []
    elif item_type == "blueprints":
        bdir = os.path.join(mnt, "blueprints")
        if os.path.isdir(bdir):
            return sorted([f.replace(".sdc", "").replace(".yaml", "").replace(".yml", "")
                          for f in os.listdir(bdir)
                          if f.endswith((".sdc", ".yaml", ".yml"))])
    elif item_type == "names":
        # Flexible: containers + blueprints
        items = []
        cdir = os.path.join(mnt, "containers")
        if os.path.isdir(cdir):
            items.extend(os.listdir(cdir))
        bdir = os.path.join(mnt, "blueprints")
        if os.path.isdir(bdir):
            items.extend([f.replace(".sdc", "").replace(".yaml", "").replace(".yml", "")
                         for f in os.listdir(bdir)
                         if f.endswith((".sdc", ".yaml", ".yml"))])
        return sorted(set(items))

    return []


def expand_fuzzy_args(argv: list[str], mnt: str) -> list[str]:
    """
    Expand fuzzy patterns in argv.
    - "n8n..." → fuzzy match with dots (prefix/suffix/infix)
    - "n8n" → exact match or fuzzy match if not exact
    - All matching is OS-independent, pure Python
    """
    if len(argv) < 2:
        return argv

    cmd = argv[0]
    expanded = [cmd]

    available = _get_available_items(cmd, mnt)

    for arg in argv[1:]:
        # Check for explicit fuzzy pattern (contains ...)
        if "..." in arg:
            matches = fuzzy_match(arg, available)
            expanded.append(matches[0] if matches else arg)
        # Also try fuzzy match on plain names if exact match not found
        elif arg not in available and available:
            matches = fuzzy_match(arg, available)
            expanded.append(matches[0] if matches else arg)
        else:
            expanded.append(arg)

    return expanded
