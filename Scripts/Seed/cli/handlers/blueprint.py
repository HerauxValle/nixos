"""
cli/handlers/blueprint.py — blueprint and format edit/validate handlers
"""

import os
from common.emit import emit
from cli.handlers._core import _mnt


def edit_blueprint(name: str, editor: str = "e", all_: bool = False) -> None:
    from orchestration.blueprint.actions import blueprint_edit as _blueprint_edit
    if all_ and not name:
        mnt = _mnt()
        bp_dir = os.path.join(mnt, "blueprints")
        errors = []
        if os.path.isdir(bp_dir):
            for f in os.listdir(bp_dir):
                if f.endswith((".sdc", ".yaml", ".yml")):
                    try:
                        _blueprint_edit(os.path.splitext(f)[0], editor)
                    except Exception as e:
                        errors.append(f"{f}: {e}")
                        emit("log", f"warning: {f}: {e}")
        if errors:
            emit("log", f"{len(errors)} blueprint(s) failed to edit")
    else:
        _blueprint_edit(name, editor)


def edit_format(name: str, editor: str = "e", all_: bool = False) -> None:
    from ui.format.actions import format_edit as _format_edit
    if all_ and not name:
        mnt = _mnt()
        fmt_dir = os.path.join(mnt, "formats")
        errors = []
        if os.path.isdir(fmt_dir):
            for f in os.listdir(fmt_dir):
                if f.endswith((".yaml", ".yml", ".json")):
                    try:
                        _format_edit(os.path.splitext(f)[0], editor)
                    except Exception as e:
                        errors.append(f"{f}: {e}")
                        emit("log", f"warning: {f}: {e}")
        if errors:
            emit("log", f"{len(errors)} format(s) failed to edit")
    else:
        _format_edit(name, editor)


def validate_blueprint(name: str, all_: bool = False) -> None:
    from orchestration.blueprint.validate import validate as _validate
    if all_ and not name:
        mnt = _mnt()
        bp_dir = os.path.join(mnt, "blueprints")
        errors = []
        if os.path.isdir(bp_dir):
            for f in os.listdir(bp_dir):
                if f.endswith((".sdc", ".yaml", ".yml")):
                    try:
                        _validate(os.path.splitext(f)[0])
                    except Exception as e:
                        errors.append(f"{f}: {e}")
                        emit("log", f"warning: {f}: {e}")
        if errors:
            emit("log", f"{len(errors)} blueprint(s) failed validation")
    else:
        _validate(name)
