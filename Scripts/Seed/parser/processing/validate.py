"""
core/parser/processing/validate.py — blueprint validation rules
"""

from parser.processing.types  import Blueprint, MainConfig
from parser.engine.ruleset    import Ruleset


def validate_blueprint(bp: Blueprint, main: MainConfig, ruleset: Ruleset) -> None:
    """Validate cross-service rules. Appends to bp.errors/warnings in place."""

    services = set(main.services)

    # duplicate service names
    seen = set()
    for name in main.services:
        if name in seen:
            bp.errors.append(f"duplicate service name: {name}")
        seen.add(name)

    # startup references unknown services
    for line in main.startup:
        if line.startswith("wait"):
            continue
        if line not in services:
            bp.errors.append(f"[startup] references unknown service: {line}")

    # wait = healthy requires health block on previous service
    prev_svc = None
    for line in main.startup:
        if line.startswith("wait") and "healthy" in line:
            if prev_svc and prev_svc in bp.parsed:
                svc = bp.parsed[prev_svc]
                if not svc.run.health:
                    bp.warnings.append(
                        f"[startup] wait=healthy on '{prev_svc}' but no [health] block defined"
                    )
        elif not line.startswith("wait"):
            prev_svc = line

    # depends references unknown service
    for svc_name, svc in bp.parsed.items():
        dep = svc.run.depends
        if dep and dep not in services:
            bp.errors.append(f"[{svc_name}] depends on unknown service: {dep}")

    # port mapping warning when network=false
    for svc_name, svc in bp.parsed.items():
        if svc.run.port and not svc.run.isolation.get("network", True):
            bp.warnings.append(
                f"[{svc_name}] port mapping ignored when network isolation is false"
            )

    # sdc_version check
    ver = main.meta.get("sdc_version", 1)
    if int(ver) > 1:
        bp.errors.append(f"unsupported sdc_version: {ver}")