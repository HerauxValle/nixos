#!/usr/bin/env python3
# Stale-config-entry warnings, checked at activation runtime instead of
# config.warnings/eval-time builtins.pathExists -- `nixos-rebuild switch`
# (as pacnix calls it) runs WITHOUT --impure, so builtins.pathExists/
# readFile on a plain string path outside the flake cannot reliably see
# the real filesystem at eval time and reports false negatives for files
# that genuinely exist. A real check at activation time always has real
# filesystem access, no such trap.
#
# Colors come from the environment (dotfilesBackupColorYellow/Reset,
# exported by ../default.nix's preamble) rather than argv -- this always
# runs as a child of that same activation script, so they're already
# inherited, no need to thread them through as extra positional args.
#
# Every message names BOTH the config.vars.dotfilesBackup entry that's at
# fault (key + file, so you can find it in config/github/*.nix without
# guessing which of possibly several entries triggered) and, for the
# "not found" case, the exact resolved value it went looking for.
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from exclude import find_matches

YELLOW = os.environ.get("dotfilesBackupColorYellow", "").encode().decode("unicode_escape")
RED = os.environ.get("dotfilesBackupColorRed", "").encode().decode("unicode_escape")
RESET = os.environ.get("dotfilesBackupColorReset", "").encode().decode("unicode_escape")


def warn(message):
    print(
        f"warning: {RED}modules/backup/dotfiles:{RESET}\n"
        f"{YELLOW}{message}{RESET}",
        file=sys.stderr,
    )


def line_contains(path, value):
    with open(path, encoding="utf-8", errors="surrogateescape") as fh:
        return any(value in line for line in fh)


def check_excludes(dotfiles_path, patterns_file):
    missing = []

    for pattern in Path(patterns_file).read_text().splitlines():
        if not pattern:
            continue
        if not find_matches(dotfiles_path, pattern):
            missing.append(pattern)

    if missing:
        warn(
            "[dotfiles-backup] ============================================\n"
            "the following excludeFiles entries do not match anything under\n"
            "dotfilesPath (renamed, typo'd, mistyped pattern, or never\n"
            "created?) and currently exclude nothing:\n\n"
            + "\n".join(f"  - {pattern}" for pattern in missing)
            + "\n\n"
            "info: these are usually just preventative excludes for\n"
            "files/directories that do not currently exist. You can\n"
            "safely ignore this warning unless you expected one of\n"
            "these entries to match.\n"
            "[dotfiles-backup] ============================================"
        )


def check_redact(dotfiles_path, checks_file):
    with open(checks_file, encoding="utf-8") as fh:
        entries = json.load(fh)
    for r in entries:
        if not r["success"]:
            warn(
                f"redactValues key '{r['key']}' (file '{r['file']}') does not resolve against config -- "
                "stale/renamed option? Skipping this entry, nothing is being redacted there right now."
            )
            continue
        path = Path(dotfiles_path) / r["file"]
        if not path.is_file():
            warn(
                f"redactValues key '{r['key']}' -- file '{r['file']}' does not exist -- "
                "renamed, typo'd, or never created? Nothing is being redacted there right now."
            )
        elif not line_contains(path, r["value"]):
            warn(
                f"redactValues key '{r['key']}' resolved to '{r['value']}', but that text does not currently "
                f"appear in '{r['file']}' -- stale entry (file changed, or this value was already "
                "redacted/commented out there)? It is not redacting anything there right now."
            )


def check_replace(dotfiles_path, checks_file):
    with open(checks_file, encoding="utf-8") as fh:
        entries = json.load(fh)
    for r in entries:
        if not r["success"]:
            warn(
                f"replaceValues key '{r['key']}' (file '{r['file']}') does not resolve against config -- "
                "stale/renamed option? Skipping this entry, nothing is being replaced there right now."
            )
            continue
        # Identified by EITHER `key` or a literal `find` string (never
        # both, see ../../default.nix's assertion) -- every message below
        # says explicitly which kind this entry is, instead of a single
        # generic "find/key" message that leaves you guessing.
        path = Path(dotfiles_path) / r["file"]
        by_key = r["key"] is not None
        kind = f"key '{r['key']}'" if by_key else f"find text '{r['value']}'"
        if not path.is_file():
            warn(
                f"replaceValues {kind} -- file '{r['file']}' does not exist -- "
                "renamed, typo'd, or never created? Nothing is being replaced there right now."
            )
        elif not line_contains(path, r["value"]):
            if by_key:
                warn(
                    f"replaceValues {kind} resolved to '{r['value']}', but that text does not currently "
                    f"appear in '{r['file']}' -- stale entry (file changed, or already replaced there)? "
                    "It is not replacing anything there right now."
                )
            else:
                warn(
                    f"replaceValues {kind} does not currently appear in '{r['file']}' -- "
                    "stale entry (file content changed)? It is not replacing anything there right now."
                )


def main():
    dotfiles_path, patterns_file, redact_checks_file, replace_checks_file = sys.argv[1:5]
    check_excludes(dotfiles_path, patterns_file)
    check_redact(dotfiles_path, redact_checks_file)
    check_replace(dotfiles_path, replace_checks_file)


if __name__ == "__main__":
    main()
