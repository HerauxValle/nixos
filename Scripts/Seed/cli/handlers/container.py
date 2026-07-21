"""
cli/handlers/container.py — container lifecycle handlers
"""

from common.emit import emit
from cli.handlers._core import _mnt, _find_blueprint, _load_svc, container_run, cleanup_stale


def run_container(a, all_: bool = False) -> None:
    from parser.processing.blueprint import load as load_bp
    from common.errors import error
    mnt   = _mnt()
    path  = _find_blueprint(a.blueprint, mnt)
    if not path:
        error("NOT_FOUND", "blueprint not found", a.blueprint)
    bp = load_bp(path)
    if bp.errors:
        error("INVALID_BLUEPRINT", "blueprint has errors", *bp.errors)
    for svc_name in bp.main.services:
        svc = bp.parsed.get(svc_name)
        if svc:
            container_run(svc, mnt, a.name if len(bp.main.services) == 1 else None)
    cleanup_stale(mnt)


def restart_container(name: str, all_: bool = False) -> None:
    from engine.container.restart import restart as container_restart_inner
    mnt = _mnt()
    if all_:
        container_restart_inner("", mnt, svc=None, all_=True)
    elif "*" in name:
        container_restart_inner(name, mnt, svc=None)
    else:
        svc = _load_svc(name, mnt)
        container_restart_inner(name, mnt, svc=svc)
