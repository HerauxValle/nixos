"""
cli/handlers/config.py — config, rules, profile, layer handlers
"""

import os
import tomllib
from common.emit import emit
from cli.handlers._core import _mnt, set_rule, unset_rule, list_rules


def profile_list() -> None:
    from orchestration.profile.list import list_profiles
    list_profiles(_mnt())

def profile_create(container: str, name: str) -> None:
    from orchestration.profile.create import create_profile
    create_profile(container, name, _mnt())

def profile_delete(container: str, name: str) -> None:
    from orchestration.profile.delete import delete_profile
    delete_profile(container, name, _mnt())

def profile_rename(container: str, old_name: str, new_name: str) -> None:
    from orchestration.profile.rename import rename_profile
    rename_profile(container, old_name, new_name, _mnt())

def profile_set_default(container: str, name: str) -> None:
    from orchestration.profile.set_default import set_default
    set_default(container, name, _mnt())


def layer_list() -> None:
    mnt  = _mnt()
    ldir = os.path.join(mnt, "layers")
    if not os.path.isdir(ldir):
        emit("action", "layers", "none"); return
    rows = []
    for name in sorted(os.listdir(ldir)):
        meta = {}
        mp   = os.path.join(ldir, name, "meta.toml")
        if os.path.isfile(mp):
            with open(mp, "rb") as f:
                meta = tomllib.load(f)
        rows.append({"id": name[:40] + "..." if len(name) > 40 else name,
                     "type": meta.get("type", "?"), "rootfs": meta.get("rootfs", "?"),
                     "refs": meta.get("refs", "0")})
    if not rows:
        emit("action", "layers", "none"); return
    emit("table", rows, type="grouped", by="type")


def rules_list() -> None:
    rows = [{"key": r["rule"], "value": str(r["value"]), "source": r["source"]}
            for r in list_rules()]
    emit("table", rows, type="flat")

def rules_set(a) -> None:
    if getattr(a, "arg1", None) != "rule":
        from common.errors import error
        error("USAGE", "usage: sd config set rule <KEY> <VALUE>")
    set_rule(a.arg2, a.arg3)
    emit("action", "set", f"{a.arg2} = {a.arg3}")

def rules_unset(a) -> None:
    if getattr(a, "arg1", None) != "rule":
        from common.errors import error
        error("USAGE", "usage: sd config unset rule <KEY>")
    unset_rule(a.arg2)
    emit("action", "unset", a.arg2)
