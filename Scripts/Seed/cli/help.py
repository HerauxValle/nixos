"""
cli/help.py — prints help table
"""

from common.emit import emit
from ui.table  import table, TABLE_SECTION_KEY


def _cmd(name, flags, desc, targets=None):
    """
    name    = command name
    flags   = flag string e.g. "-n, -s" or ""
    desc    = what it does
    targets = list of sub-target strings (become children)
    """
    row = {"command": name, "flags": flags, "info": desc}
    if targets:
        row["children"] = [
            {"command": t["name"], "flags": t.get("flags", ""), "info": t.get("desc", "")}
            for t in targets
        ]
    return row


def _flag(f, desc):
    return {"name": f, "flags": "", "desc": desc}

def _target(name, desc=""):
    return {"name": name, "flags": "", "desc": desc}


TREE = [
    {TABLE_SECTION_KEY: "Resources (Primary)"},
    _cmd("image", "-n -s -d", "manage image files", [
        _target("create",  "create new LUKS+btrfs image [-n NAME] [-s SIZE]"),
        _target("delete",  "permanently delete image"),
        _target("list",    "list all images"),
        _target("select",  "mount and activate image [-d DEPTH]"),
        _target("close",   "unmount and close image"),
        _target("which",   "show currently active image"),
    ]),
    _cmd("container", "-n -all -f -lines", "manage containers", [
        _target("run",     "build layers and start container"),
        _target("stop",    "stop a running container"),
        _target("exec",    "run a command inside container [-all]"),
        _target("logs",    "view container output [-f] [-lines N]"),
        _target("restart", "stop then start container"),
        _target("delete",  "permanently delete container"),
        _target("list",    "list all containers"),
        _target("prune",   "remove unreferenced layers [-all]"),
    ]),
    _cmd("blueprint", "-n -e -ext", "manage blueprints", [
        _target("create",   "create new .sdc blueprint [-ext EXTENSION]"),
        _target("delete",   "permanently delete blueprint"),
        _target("list",     "list all blueprints"),
        _target("validate", "validate a blueprint file"),
        _target("edit",     "open in editor [-e EDITOR]"),
    ]),
    _cmd("format", "-e", "manage custom parsers", [
        _target("create", "create new custom parser ruleset"),
        _target("delete", "permanently delete format"),
        _target("list",   "list all formats"),
        _target("edit",   "open in editor [-e EDITOR]"),
    ]),
    _cmd("profile", "-container -n", "manage container profiles", [
        _target("create",  "create profile [-container ID] [-n NAME]"),
        _target("delete",  "delete profile [-container ID] [-n NAME]"),
        _target("list",    "list all profiles"),
        _target("rename",  "rename profile or verified system"),
        _target("default", "set default profile [-container ID]"),
    ]),
    _cmd("config", "", "manage image configuration", [
        _target("list",  "show all config rules"),
        _target("reset", "reset to defaults"),
        _target("set",   "override a rule [rule KEY VALUE]"),
        _target("unset", "remove a rule override [rule KEY]"),
        _target("edit",  "open in editor [-e EDITOR]"),
    ]),
    {TABLE_SECTION_KEY: "Encryption & Security"},
    _cmd("encryption", "-n -preset", "manage LUKS encryption and KDF", [
        _target("add",       "add passkey to user slot [-n NAME]"),
        _target("create",    "create custom KDF preset [-argon2-memory M] [-argon2-time T] [-argon2-parallel P]"),
        _target("delete",    "remove custom preset"),
        _target("list",      "show user slots, verified systems, or all"),
        _target("verify",    "register host and add derived key [-n NAME]"),
        _target("unverify",  "remove host's verified key"),
        _target("rename",    "rename slot or verified system"),
        _target("refresh",   "rotate internal keyfiles [auth]"),
        _target("enable",    "remove hardcoded passkey (activate real encryption)"),
        _target("disable",   "restore hardcoded passkey"),
    ]),
    {TABLE_SECTION_KEY: "Utilities & Info"},
    _cmd("layers", "", "list all image layers"),
    _cmd("processes", "", "list processes in containers"),
    _cmd("rules", "", "list all rule definitions"),
    _cmd("db", "NAME", "show a help document"),
    _cmd("help", "", "show this table"),
]


def show_help() -> None:
    emit("table", TREE, type="tree", tree_col="command")