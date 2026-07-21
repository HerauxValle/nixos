"""
core/parser/processing/run.py — parse [run] block into RunConfig
"""

from parser.engine.parser       import Node
from parser.processing.types    import RunConfig, StorageNode
from parser.processing.storage  import parse_storage
from parser.processing.defaults import apply_defaults


def _find_child(node: Node, name: str) -> Node | None:
    for child in node.children:
        if child.name.lower() == name.lower():
            return child
    return None


def _parse_storage(node: Node, svc_name: str) -> list[StorageNode]:
    """Parse [storage] kv block — key=mount_path."""
    nodes = []
    for k, v in node.kv.items():
        nodes.append(StorageNode(name=k, mount=str(v)))
    # also handle nested storage blocks
    for child in node.children:
        for k, v in child.kv.items():
            nodes.append(StorageNode(
                name=f"{child.name}/{k}",
                mount=str(v)
            ))
    return nodes


def parse_run(node: Node, svc_name: str, env: dict,
              defs: dict) -> tuple[RunConfig, list[str], list[str]]:
    """
    Parse [run]:[ ... ]: into RunConfig.
    Returns (RunConfig, errors, warnings).
    """
    errors   = []
    warnings = []
    cfg      = RunConfig()

    config_node = _find_child(node, "config")
    if config_node:
        raw_cfg, errs = apply_defaults("config", dict(config_node.kv), defs)
        errors += [f"[{svc_name}] {e}" for e in errs]
        cfg.entrypoint  = str(raw_cfg.get("entrypoint",  ""))
        cfg.port        = str(raw_cfg.get("port",        ""))
        cfg.restart     = str(raw_cfg.get("restart",     "no"))
        cfg.restart_max = int(raw_cfg.get("restart_max", 0))
        cfg.user        = str(raw_cfg.get("user",        ""))
        cfg.workdir     = str(raw_cfg.get("workdir",     "/"))
        cfg.depends     = str(raw_cfg.get("depends",     ""))

        # validate restart logic
        if cfg.restart == "always" and cfg.restart_max > 0:
            errors.append(f"[{svc_name}] restart=always conflicts with restart_max={cfg.restart_max}")

    env_node = _find_child(node, "env")
    if env_node:
        merged = dict(env)           # global service env first
        merged.update(env_node.kv)   # run-level env overrides
        cfg.env = merged
    else:
        cfg.env = dict(env)

    res_node = _find_child(node, "resources")
    if res_node:
        cfg.resources, _ = apply_defaults("resources", dict(res_node.kv), defs)
    else:
        cfg.resources, _ = apply_defaults("resources", {}, defs)

    iso_node = _find_child(node, "isolation")
    if iso_node:
        cfg.isolation, _ = apply_defaults("isolation", dict(iso_node.kv), defs)
    else:
        cfg.isolation, _ = apply_defaults("isolation", {}, defs)

    health_node = _find_child(node, "health")
    if health_node:
        cfg.health, _ = apply_defaults("health", dict(health_node.kv), defs)

    storage_node = _find_child(node, "storage")
    if storage_node:
        cfg.storage = _parse_storage(storage_node, svc_name)

    security_node = _find_child(node, "security")
    if security_node:
        security_preset = str(security_node.kv.get("profile", "")).strip()
        if security_preset:
            if security_preset not in ("strict", "default", "permissive"):
                errors.append(
                    f"[{svc_name}] invalid security profile: {security_preset} "
                    "(must be: strict, default, or permissive)"
                )
            else:
                cfg.security_preset = security_preset

    return cfg, errors, warnings