"""
core/container/restart.py — restart a container
"""
from common.emit import emit

import os


def _find_matching_containers(mnt: str, pattern: str) -> list[str]:
    """Find all containers matching the pattern."""
    import fnmatch
    cdir = os.path.join(mnt, "containers")
    if not os.path.isdir(cdir):
        return []
    return [name for name in os.listdir(cdir) if fnmatch.fnmatch(name, pattern)]


def restart(container_name: str, mnt: str, svc=None, all_: bool = False) -> int:
    """Stop then start a container, reusing existing rootfs."""
    from engine.container.stop import stop
    from engine.container.run  import _start_container
    from common.errors import error

    # Handle -all flag
    if all_:
        cdir = os.path.join(mnt, "containers")
        if not os.path.isdir(cdir):
            return 0
        for name in sorted(os.listdir(cdir)):
            path = os.path.join(cdir, name)
            if os.path.isdir(path):
                try:
                    import tomllib
                    meta_path = os.path.join(path, "meta.toml")
                    meta = {}
                    if os.path.isfile(meta_path):
                        with open(meta_path, "rb") as f:
                            meta = tomllib.load(f)
                    # Load service for this container
                    svc_name = meta.get("service", "")
                    if svc_name:
                        from cli.handlers import _find_blueprint
                        bp_path = _find_blueprint(svc_name, mnt)
                        if bp_path:
                            from parser.processing.blueprint import load as load_bp
                            bp = load_bp(bp_path)
                            svc_obj = bp.parsed.get(svc_name)
                            if svc_obj:
                                restart(name, mnt, svc=svc_obj)
                except Exception:
                    pass
        return 0

    # Handle pattern matching
    if "*" in container_name:
        matching = _find_matching_containers(mnt, container_name)
        if not matching:
            error("NOT_FOUND", "no containers match pattern", container_name)
        for name in matching:
            try:
                import tomllib
                path = os.path.join(mnt, "containers", name)
                meta_path = os.path.join(path, "meta.toml")
                meta = {}
                if os.path.isfile(meta_path):
                    with open(meta_path, "rb") as f:
                        meta = tomllib.load(f)
                svc_name = meta.get("service", "")
                if svc_name:
                    from cli.handlers import _find_blueprint
                    bp_path = _find_blueprint(svc_name, mnt)
                    if bp_path:
                        from parser.processing.blueprint import load as load_bp
                        bp = load_bp(bp_path)
                        svc_obj = bp.parsed.get(svc_name)
                        if svc_obj:
                            restart(name, mnt, svc=svc_obj)
            except Exception:
                pass
        return 0

    containers_dir = os.path.join(mnt, "containers")
    container_path = os.path.join(containers_dir, container_name)

    if not os.path.isdir(container_path):
        error("NOT_FOUND", "container not found", container_name)

    emit("log", f"restarting {container_name}")
    stop(container_name, mnt, force=True)

    rootfs = os.path.join(container_path, "rootfs")
    return _start_container(container_path, rootfs, svc, mnt, container_name)