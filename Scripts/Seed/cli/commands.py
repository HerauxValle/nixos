"""
cli/commands.py — dispatch tables + schema (resource-first model)
"""

from cli.parser   import cmd, parse
from cli.handlers import *
from cli.handlers._core import _mnt, _find_blueprint, _load_svc
from cli.handlers.encryption import (_enc_add_handler, _enc_create_handler,
    _enc_delete_handler, _enc_list_handler, _enc_refresh_handler)
from cli.all_handler import handle_all


# ── dispatch tables ───────────────────────────────────────────────────────────

IMAGE_ACTIONS = {
    "create": lambda a: create_image(a),
    "delete": lambda a: img_delete(a.path),
    "list":   lambda a: list_images(),
    "select": lambda a: select(a.path, depth=getattr(a, 'd', 3)),
    "close":  lambda a: close_all() if (getattr(a, 'name', None) == "all" or getattr(a, 'all', False)) else close_active() if not getattr(a, 'name', None) else close(getattr(a, 'name', None)),
    "which":  lambda a: which_image(),
}

CONTAINER_ACTIONS = {
    "run":     lambda a: run_container(a, all_=getattr(a, 'all', False)),
    "stop":    lambda a: container_stop(getattr(a, 'name', "") or "", _mnt(), all_=getattr(a, 'all', False)),
    "exec":    lambda a: exec_cmd(getattr(a, 'name', "") or "", _mnt(), getattr(a, 'cmd', []), all_=getattr(a, 'all', False)),
    "logs":    lambda a: container_logs(getattr(a, 'name', "") or "", _mnt(), getattr(a, 'f', False), getattr(a, 'lines', 50), all_=getattr(a, 'all', False)),
    "restart": lambda a: restart_container(getattr(a, 'name', "") or "", getattr(a, 'all', False)),
    "delete":  lambda a: container_delete(a.path, _mnt(), all_=getattr(a, 'all', False)),
    "list":    lambda a: list_containers(_mnt()),
    "prune":   lambda a: prune(_mnt(), getattr(a, 'all', False)),
}

BLUEPRINT_ACTIONS = {
    "create":   lambda a: blueprint_add(a.path, a.ext or ".sdc"),
    "delete":   lambda a: blueprint_delete(a.path),
    "list":     lambda a: blueprint_list(),
    "validate": lambda a: validate_blueprint(a.path or "", all_=getattr(a, 'all', False)),
    "edit":     lambda a: edit_blueprint(a.path or "", a.e, all_=getattr(a, 'all', False)),
}

FORMAT_ACTIONS = {
    "create": lambda a: format_add(a.path),
    "delete": lambda a: format_delete(a.path),
    "list":   lambda a: format_list(),
    "edit":   lambda a: edit_format(a.name or "", a.e, all_=getattr(a, 'all', False)),
}

PROFILE_ACTIONS = {
    "create":  lambda a: profile_create(a.container, a.name),
    "delete":  lambda a: profile_delete(a.container, a.name),
    "list":    lambda a: profile_list(),
    "rename":  lambda a: profile_rename(a.container, a.arg1, a.arg2),
    "default": lambda a: profile_set_default(a.container, a.arg1),
}

CONFIG_ACTIONS = {
    "list":  lambda a: config_list(),
    "reset": lambda a: config_reset(),
    "set":   lambda a: rules_set(a),
    "unset": lambda a: rules_unset(a),
    "edit":  lambda a: config_edit(a.arg1 or "", a.e),
}

ENCRYPTION_SUBCMDS = {
    "add":       lambda a: _enc_add_handler(a),
    "create":    lambda a: _enc_create_handler(a),
    "delete":    lambda a: _enc_delete_handler(a),
    "list":      lambda a: _enc_list_handler(a),
    "verify":    lambda a: verify_host(getattr(a, 'name', None)),
    "unverify":  lambda a: unverify_host(a.arg1 or a.arg2 or ""),
    "rename":    lambda a: rename_slot(a.arg1 or "", a.arg2 or ""),
    "refresh":   lambda a: _enc_refresh_handler(a),
    "enable":    lambda a: enable_encryption(),
    "disable":   lambda a: disable_encryption(),
}


# ── schema ────────────────────────────────────────────────────────────────────

SCHEMA = {
    # Help & System
    "help": cmd(func=lambda a: show_help()),
    "db":   cmd("name", func=lambda a: db_show(a.name)),

    # Resource-first model (primary)
    "image":      cmd("action", "path?", flags="-name/-n -size/-s -ext -c/flag -d/int=3 -all/flag", dispatch=IMAGE_ACTIONS),
    "container":  cmd("action", "name?", flags="-all/flag -f/flag -lines/int=50 -cmd...", dispatch=CONTAINER_ACTIONS),
    "blueprint":  cmd("action", "path?", flags="-name/-n -ext -e -all/flag", dispatch=BLUEPRINT_ACTIONS),
    "format":     cmd("action", "path?", flags="-name/-n -e -all/flag", dispatch=FORMAT_ACTIONS),
    "profile":    cmd("action", "arg1?", "arg2?", "arg3?", flags="-name/-n -container -all/flag", dispatch=PROFILE_ACTIONS),
    "config":     cmd("action", "arg1?", "arg2?", "arg3?", flags="-e -all/flag", dispatch=CONFIG_ACTIONS),
    "encryption": cmd("subcmd", "arg1?", "arg2?", flags="-name/-n -preset -argon2-memory -argon2-time -argon2-parallel", dispatch=ENCRYPTION_SUBCMDS),

    # Utility shortcuts
    "layers":     cmd(func=lambda a: layer_list()),
    "processes":  cmd(func=lambda a: list_processes()),
    "rules":      cmd(func=lambda a: rules_list()),
}


def register(argv: list[str]) -> tuple:
    # ── DEV ONLY — requires SD_DEV=1 env var ─────────────────────────────────
    import os
    if os.environ.get("SD_DEV") == "1":
        _test_script = os.path.join(os.path.dirname(__file__), "../tests/script.sh")
        if os.path.isfile(_test_script):
            from tests.cmd import penetrate
            SCHEMA["penetrate"] = cmd("suite?", func=lambda a: penetrate(a.suite or "all"))
    # ─────────────────────────────────────────────────────────────────────────
    return parse(SCHEMA, argv)