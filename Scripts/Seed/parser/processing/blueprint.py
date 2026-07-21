"""
core/parser/processing/blueprint.py — orchestrates parsing a .sdc file
"""

import os

from parser.engine.parser        import parse_text, Node
from parser.engine.ruleset       import Ruleset, find_format
from parser.processing.types     import Blueprint, Service, MainConfig
from parser.processing.build     import parse_build
from parser.processing.run       import parse_run
from parser.processing.validate  import validate_blueprint
from parser.processing.defaults  import load_defaults

_DEFAULTS = None


def _get_defaults() -> dict:
    global _DEFAULTS
    if _DEFAULTS is None:
        _DEFAULTS = load_defaults()
    return _DEFAULTS


def _find_child(node: Node, name: str) -> Node | None:
    for child in node.children:
        if child.name.lower() == name.lower():
            return child
    return None


def _parse_main(tree) -> tuple[MainConfig, list[str], list[str]]:
    errors   = []
    warnings = []
    main_cfg = MainConfig()

    main_node = _find_child(tree.root, "main")
    if not main_node:
        errors.append("missing [main] block")
        return main_cfg, errors, warnings

    meta_node = _find_child(main_node, "meta")
    if meta_node:
        main_cfg.meta = dict(meta_node.kv)
        ver = main_cfg.meta.get("sdc_version", 1)
        if int(ver) != 1:
            errors.append(f"unsupported sdc_version: {ver} (supported: 1)")

    svc_node = _find_child(main_node, "services")
    if svc_node:
        main_cfg.services = [l.strip() for l in svc_node.raw if l.strip()]
    else:
        errors.append("[main] missing [services] block")

    startup_node = _find_child(main_node, "startup")
    if startup_node:
        main_cfg.startup = [l.strip() for l in startup_node.raw if l.strip()]

    return main_cfg, errors, warnings


def _get_ruleset(text: str) -> Ruleset:
    first = text.splitlines()[0].strip() if text.strip() else ""
    if first.startswith("#!") and first[2:].strip() not in ("sdc", ""):
        fmt     = first[2:].strip()
        fmt_dir = _get_formats_dir()
        return find_format(fmt, fmt_dir)
    try:
        from common.config import get_config_path
        return Ruleset(get_config_path("ruleset"))
    except Exception:
        return Ruleset(None)


def _get_formats_dir() -> str:
    try:
        from common.session import get_active
        img_formats = os.path.join(get_active(), "formats")
        if os.path.isdir(img_formats):
            return img_formats
    except Exception:
        pass
    from common.config import PROJECT_CONFIG
    return PROJECT_CONFIG


def _interpret(tree, ruleset: Ruleset) -> Blueprint:
    defs = _get_defaults()

    main_cfg, errs, warns = _parse_main(tree)
    bp          = Blueprint(main=main_cfg)
    bp.errors   = list(tree.errors) + errs
    bp.warnings = list(tree.warnings) + warns

    if bp.errors:
        return bp

    for svc_name in main_cfg.services:
        node = _find_child(tree.root, svc_name)
        if node is None:
            bp.errors.append(f"[{svc_name}] declared in [services] but no block found")
            continue

        svc = Service(name=svc_name)

        meta_node = _find_child(node, "meta")
        if meta_node:
            svc.meta = dict(meta_node.kv)

        # service-level env (available in both build and run)
        env_node  = _find_child(node, "env")
        svc_env   = dict(env_node.kv) if env_node else {}

        build_node = _find_child(node, "build")
        if build_node:
            svc.build, errs, warns = parse_build(build_node, svc_name, svc_env)
            bp.errors   += errs
            bp.warnings += warns
        else:
            bp.warnings.append(f"[{svc_name}] missing [build] block")

        run_node = _find_child(node, "run")
        if run_node:
            svc.run, errs, warns = parse_run(run_node, svc_name, svc_env, defs)
            bp.errors   += errs
            bp.warnings += warns
        else:
            bp.warnings.append(f"[{svc_name}] missing [run] block")

        bp.parsed[svc_name] = svc

    validate_blueprint(bp, main_cfg, ruleset)
    return bp


def load(path: str) -> Blueprint:
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    ruleset = _get_ruleset(text)
    tree    = parse_text(text, ruleset)
    return _interpret(tree, ruleset)


def loads(text: str) -> Blueprint:
    ruleset = _get_ruleset(text)
    tree    = parse_text(text, ruleset)
    return _interpret(tree, ruleset)