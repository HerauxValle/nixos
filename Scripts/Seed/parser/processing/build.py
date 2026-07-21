"""
core/parser/processing/build.py — parse [build] block into BuildConfig
"""

from parser.engine.parser       import Node
from parser.processing.types    import BuildConfig
from parser.processing.deps     import parse_deps


def _find_child(node: Node, name: str) -> Node | None:
    for child in node.children:
        if child.name.lower() == name.lower():
            return child
    return None


def parse_build(node: Node, svc_name: str, env: dict) -> tuple[BuildConfig, list[str], list[str]]:
    """
    Parse [build]:[ ... ]: into BuildConfig.
    Returns (BuildConfig, errors, warnings).
    """
    errors   = []
    warnings = []
    cfg      = BuildConfig()

    general = _find_child(node, "general")
    if not general:
        errors.append(f"[{svc_name}] [build] missing [general] block")
        return cfg, errors, warnings

    cfg.rootfs = general.kv.get("rootfs", "")
    if not cfg.rootfs:
        errors.append(f"[{svc_name}] [general] missing required field: rootfs")

    deps_node = _find_child(general, "deps")
    if deps_node:
        cfg.deps = parse_deps(deps_node.raw)
    elif "deps" in general.kv:
        # single-line deps = curl ca-certificates zstd
        # Convert to list of ("pkg", "package1 package2 ...") tuples
        if isinstance(general.kv["deps"], str):
            cfg.deps = [("pkg", general.kv["deps"])]
        else:
            cfg.deps = []

    install_node = _find_child(node, "install")
    if install_node:
        cfg.install = [l for l in install_node.raw if l.strip()]

    return cfg, errors, warnings