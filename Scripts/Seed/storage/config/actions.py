"""
core/config/actions.py — list, edit, reset config
"""
from common.emit import emit

import os
import shutil
import subprocess

from common.config import list_configs, reset_config, KNOWN_SHEBANGS, PROJECT_CONFIG
from ui.table    import table
from lib.variables.colors import c, DEFAULT, DEFAULT_SUCCESS, DEFAULT_WARN, BRED, BBLACK
from lib.variables.general import *




def _find_editor(override: str | None) -> str:
    if override:
        return override
    editor = os.environ.get("EDITOR")
    if editor:
        return editor
    for e in EDITOR_FALLBACKS:
        if shutil.which(e):
            return e
    from common.errors import error
    error("NO_EDITOR", "no editor found", "set $EDITOR or use -e")


def config_list() -> None:
    from common.session import get_active
    mnt  = get_active()
    rows = list_configs(mnt)

    emit("table", rows, type="flat")


def config_edit(name: str, editor_override: str | None = None) -> None:
    from common.session import get_active
    from common.errors  import error

    if not name:
        error("MISSING_ARG", "config name required")

    mnt        = get_active()
    config_dir = os.path.join(mnt, "config")

    if not os.path.isdir(config_dir):
        error("NOT_FOUND", "config directory not found", config_dir)

    if "." not in name:
        matches = [f for f in os.listdir(config_dir)
                   if os.path.splitext(f)[0] == name]
        if not matches:
            from common.shebang import scan_dir
            found = scan_dir(config_dir)
            if name in found:
                matches = [os.path.relpath(found[name], config_dir)]
        if not matches:
            error("NOT_FOUND", f"config file '{name}' not found", f"available: {', '.join([os.path.splitext(f)[0] for f in os.listdir(config_dir)])}")
        if len(matches) > 1:
            error("AMBIGUOUS", f"multiple config files named '{name}'", *matches,
                  "specify extension to select one")
        name = matches[0]

    path = os.path.join(config_dir, name)
    if not os.path.isfile(path):
        error("NOT_FOUND", "config file not found", path)

    editor = _find_editor(editor_override)
    emit("log", f"opening {path} with {editor}...")
    subprocess.call([editor, path])
    emit("action", "saved", name)


def config_reset() -> None:
    from common.session import get_active
    mnt = get_active()
    reset_config(mnt)
    emit("action", "reset", "config")