"""
cli/handlers/_core.py — shared utilities: lazy imports, _mnt, _find_blueprint
"""

import os
import importlib as _il
from common.emit import emit


def _lazy(module, name, alias=None):
    def _get(*a, **kw):
        mod = _il.import_module(module)
        fn = getattr(mod, name)
        return fn(*a, **kw)
    _get.__name__ = alias or name
    return _get


create           = _lazy("engine.image.create",         "create")
parse_size       = _lazy("engine.image.create",         "parse_size")
img_delete       = _lazy("engine.image.delete",         "delete")
close            = _lazy("engine.image.close",          "close")
close_all        = _lazy("engine.image.close",          "close_all")
close_active     = _lazy("engine.image.close",          "close_active")
_select_img      = _lazy("engine.image.select",         "select")
list_images      = _lazy("engine.image.list",           "list_images")
which_image      = _lazy("engine.image.list",           "which_image")
blueprint_add    = _lazy("orchestration.blueprint.actions",  "blueprint_add")
blueprint_edit   = _lazy("orchestration.blueprint.actions",  "blueprint_edit")
blueprint_list   = _lazy("orchestration.blueprint.actions",  "blueprint_list")
blueprint_delete = _lazy("orchestration.blueprint.actions",  "blueprint_delete")
validate         = _lazy("orchestration.blueprint.validate", "validate")
format_add       = _lazy("ui.format.actions",           "format_add")
format_edit      = _lazy("ui.format.actions",           "format_edit")
format_list      = _lazy("ui.format.actions",           "format_list")
format_delete    = _lazy("ui.format.actions",           "format_delete")
db_list          = _lazy("storage.db.actions",          "db_list")
db_show          = _lazy("storage.db.actions",          "db_show")
config_list      = _lazy("storage.config.actions",      "config_list")
config_edit      = _lazy("storage.config.actions",      "config_edit")
config_reset     = _lazy("storage.config.actions",      "config_reset")
show_help        = _lazy("cli.help",                    "show_help")
container_run    = _lazy("engine.container.run",        "run", "container_run")
list_containers  = _lazy("engine.container.list",       "list_containers")
container_restart= _lazy("engine.container.restart",    "restart", "container_restart")
container_delete = _lazy("engine.container.delete",     "delete", "container_delete")
container_stop   = _lazy("engine.container.stop",       "stop", "container_stop")
cleanup_stale    = _lazy("engine.container.stop",       "cleanup_stale")
exec_cmd         = _lazy("engine.container.exec",       "exec_cmd")
container_logs   = _lazy("engine.container.logs",       "logs", "container_logs")
prune            = _lazy("engine.layer.prune",          "prune")
list_processes   = _lazy("engine.process.list",         "list_processes")
set_rule         = _lazy("orchestration.settings",      "set_rule")
unset_rule       = _lazy("orchestration.settings",      "unset_rule")
list_rules       = _lazy("orchestration.settings",      "list_rules")


__all__ = [
    "show_help", "close", "close_all", "close_active",
    "list_images", "which_image", "img_delete",
    "blueprint_add", "blueprint_edit", "blueprint_list", "blueprint_delete", "validate",
    "format_add", "format_edit", "format_list", "format_delete",
    "db_list", "db_show", "config_list", "config_edit", "config_reset",
    "container_run", "list_containers", "container_restart", "container_delete",
    "container_stop", "cleanup_stale", "exec_cmd", "container_logs",
    "prune", "list_processes",
    "set_rule", "unset_rule", "list_rules",
    "_mnt", "_find_blueprint", "_load_svc",
]


def _mnt() -> str:
    from common.session import get_active
    from common.errors import error
    from lib.variables.general import IMG_ENV_VAR
    mnt = get_active()
    if mnt:
        return mnt
    from engine.image.resolver import resolve_img
    from engine.image.header import update_last_used
    auto = resolve_img()
    if auto:
        emit("info", f"auto-selected {os.path.basename(auto)}")
        _select_img(auto)
        update_last_used(auto)
        mnt = get_active()
        if mnt:
            return mnt
    error("NO_IMG", "no img selected",
          f"use 'sd select <path>' or set {IMG_ENV_VAR}")


def _load_svc(container_name: str, mnt: str):
    from parser.processing.blueprint import load as load_bp
    from common.errors import error
    import tomllib
    meta_path = os.path.join(mnt, "containers", container_name, "meta.toml")
    if not os.path.isfile(meta_path):
        error("NOT_FOUND", "container not found", container_name)
    with open(meta_path, "rb") as f:
        meta = tomllib.load(f)
    svc_name = meta.get("service", "")
    bp_path  = _find_blueprint(svc_name, mnt)
    if not bp_path:
        error("NOT_FOUND", f"blueprint for '{svc_name}' not found")
    bp = load_bp(bp_path)
    return bp.parsed.get(svc_name)


_bp_cache = {}

def _find_blueprint(name: str, mnt: str) -> str | None:
    def _get_index(folder: str) -> dict:
        if folder not in _bp_cache:
            if not os.path.isdir(folder):
                _bp_cache[folder] = {}
            else:
                _bp_cache[folder] = {
                    os.path.splitext(f)[0]: os.path.join(folder, f)
                    for f in os.listdir(folder)
                }
        return _bp_cache[folder]
    internal = _get_index(os.path.join(mnt, "blueprints")).get(name)
    if internal:
        return internal
    from orchestration.settings import get_external_blueprints_dir
    ext_dir = get_external_blueprints_dir()
    if ext_dir:
        return _get_index(ext_dir).get(name)
    return None
