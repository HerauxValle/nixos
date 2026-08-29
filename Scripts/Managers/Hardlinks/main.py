#!/usr/bin/env python3
# &desc: "Hardlink manager (hlm) -- tracks hardlinks created from originals in a JSON store, with a short id, so broken/stale links can be detected and pruned."
"""hlm — hardlink manager. Tracks hardlinks created from originals, with a short id."""

import argparse
import json
import os
import random
import shutil
import string
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT_PATH = Path(__file__).resolve()
# State (metadata.json/.hlm_default/imports.json) is hardcoded to the source
# checkout, not SCRIPT_DIR -- once Nix-packaged (flake.nix here), SCRIPT_DIR
# resolves inside the read-only /nix/store, so state can't live next to the
# script anymore. Tracked in ~/Dotfiles/.hardcodedpaths.md.
STATE_DIR = Path("/home/herauxvalle/Dotfiles/Scripts/Managers/Hardlinks")
# HLM_METADATA_PATH overrides where the metadata store lives, for one-off use
# without touching the persistent default — same precedence it always had.
# Falls back to whatever --config @default last set; falls back further to
# metadata.json next to the script if @default was never used (fully
# backward compatible — nothing changes for anyone who never touches --config).
DEFAULT_CONF_POINTER = STATE_DIR / ".hlm_default"
LEGACY_META_PATH = STATE_DIR / "metadata.json"
META_PATH = (
    Path(os.environ["HLM_METADATA_PATH"]) if os.environ.get("HLM_METADATA_PATH")
    else (Path(DEFAULT_CONF_POINTER.read_text().strip()) if DEFAULT_CONF_POINTER.exists()
          else LEGACY_META_PATH)
)
BIN_DIR = Path.home() / ".local" / "bin"
BIN_LINK = BIN_DIR / "hlm"

# ── colors (style lifted from smg) ──────────────────────────────────────────
BOLD = "\033[1m"
RESET = "\033[0m"
GREEN = "\033[0;32m"
RED = "\033[0;31m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
DIM = "\033[2m"


def err(msg: str) -> None:
    print(f"{RED}{BOLD}error:{RESET} {msg}", file=sys.stderr)
    sys.exit(1)


def warn(msg: str) -> None:
    print(f"{YELLOW}{BOLD}warning:{RESET} {msg}")


def ok(msg: str) -> None:
    print(f"{GREEN}{BOLD}✓{RESET} {msg}")


# ── metadata persistence ────────────────────────────────────────────────────
def load_meta(path: Path = None) -> list:
    path = path or META_PATH
    if not path.exists():
        return []
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return []


def save_meta(entries: list, path: Path = None) -> None:
    (path or META_PATH).write_text(json.dumps(entries, indent=2))


# ── --config: select/create/alias a metadata store ─────────────────────────
# A "conf" is just metadata.json under a different name/location — same JSON
# array of entries, selectable per-invocation instead of being fixed next to
# the script. This is what lets e.g. a Jellyfin-only link tracker live
# separately from the main one. The default filename inside a directory is
# "metadata.json" — same name it's always had, not a new filename — *.json
# is only special-cased for an explicit, literally-named file path.

def _ensure_conf_file(f: Path) -> Path:
    f = f.expanduser()
    if not f.exists():
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text("[]")
        return f.resolve()
    try:
        data = json.loads(f.read_text())
        if not isinstance(data, list):
            raise ValueError
    except Exception:
        err(f"--config: {f} exists but is not a valid hlm metadata file (expected a JSON array)")
    return f.resolve()


def _ensure_conf_in_dir(d: Path) -> Path:
    d = d.expanduser()
    d.mkdir(parents=True, exist_ok=True)
    return _ensure_conf_file(d / "metadata.json")


def resolve_conf_target(raw: str) -> Path:
    """A plain --config argument: @pwd, a directory, or a *.json path.
    Creates whatever's missing along the way."""
    if raw == "@pwd":
        return _ensure_conf_in_dir(Path.cwd())
    p = Path(raw).expanduser()
    if p.suffix == ".json":
        return _ensure_conf_file(p)
    return _ensure_conf_in_dir(p)


def resolve_conf_target_readonly(raw: str) -> Path:
    """Same resolution as resolve_conf_target, but never creates anything —
    for --list/@verify/@remove, where a missing target just means 'nothing
    here' rather than something to bring into existence."""
    if raw == "@pwd":
        return Path.cwd() / "metadata.json"
    p = Path(raw).expanduser()
    if p.suffix == ".json":
        return p
    return p / "metadata.json"


def imports_conf_path_for(conf_path: Path) -> Path:
    return conf_path.parent / "imports.json"


def load_imports(conf_path: Path) -> dict:
    p = imports_conf_path_for(conf_path)
    if not p.exists():
        return {}
    try:
        data = json.loads(p.read_text())
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_imports(conf_path: Path, data: dict) -> None:
    imports_conf_path_for(conf_path).write_text(json.dumps(data, indent=2))


def resolve_alias(alias: str, context_conf: Path) -> Path:
    imports = load_imports(context_conf)
    if alias not in imports:
        err(f"--config #{alias}: no such alias (registered against "
            f"{imports_conf_path_for(context_conf)})")
    return resolve_conf_target(imports[alias])


def resolve_alias_readonly(alias: str, context_conf: Path) -> Path | None:
    imports = load_imports(context_conf)
    if alias not in imports:
        return None
    return resolve_conf_target_readonly(imports[alias])


def resolve_config_arg(raw: str, context_conf: Path) -> Path:
    if raw.startswith("#"):
        return resolve_alias(raw[1:], context_conf)
    return resolve_conf_target(raw)


def resolve_config_arg_readonly(raw: str, context_conf: Path) -> Path | None:
    if raw.startswith("#"):
        return resolve_alias_readonly(raw[1:], context_conf)
    return resolve_conf_target_readonly(raw)


def consume_config_directives(argv: list) -> tuple:
    """Strip every --config occurrence (and its arguments) out of argv,
    returning (remaining_argv, ordered_directives). --config can appear
    anywhere as long as it isn't placed inside another flag's own argument
    slots — this just scans token-by-token, it doesn't know about other
    flags' arities, so that constraint is on the caller's command line, not
    enforced here."""
    cleaned, directives = [], []
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok != "--config":
            cleaned.append(tok)
            i += 1
            continue
        if i + 1 >= len(argv):
            err("--config requires an argument")
        nxt = argv[i + 1]
        if nxt == "@import":
            if i + 3 >= len(argv):
                err("usage: --config @import <dir> <alias>")
            directives.append(("import", argv[i + 2], argv[i + 3]))
            i += 4
        elif nxt == "@default":
            if i + 2 >= len(argv):
                err("usage: --config @default <path>")
            directives.append(("default", argv[i + 2]))
            i += 3
        elif nxt == "@verify":
            directives.append(("verify",))
            i += 2
        elif nxt == "@remove":
            if i + 2 >= len(argv):
                err("usage: --config @remove <#alias|dir|*.json>")
            directives.append(("remove", argv[i + 2]))
            i += 3
        else:
            directives.append(("select", nxt))
            i += 2
    return cleaned, directives


def apply_config_directives(directives: list) -> Path:
    """Returns the conf path active for this invocation. Reassigns the
    module-level META_PATH so load_meta/save_meta pick it up."""
    global META_PATH
    active = META_PATH
    for directive in directives:
        kind = directive[0]
        if kind == "select":
            active = resolve_config_arg(directive[1], active)
        elif kind == "import":
            _, dir_arg, alias = directive
            target = resolve_config_arg(dir_arg, active)
            imports = load_imports(active)
            imports[alias] = str(target)
            save_imports(active, imports)
            ok(f"alias #{alias} -> {target}  (in {imports_conf_path_for(active)})")
        elif kind == "default":
            target = resolve_config_arg(directive[1], active)
            DEFAULT_CONF_POINTER.write_text(str(target))
            ok(f"default conf set to {target}")
        elif kind == "verify":
            cmd_config_verify(active)
        elif kind == "remove":
            cmd_config_remove(active, directive[1])
    META_PATH = active
    return active


def cmd_config_verify(context_conf: Path) -> None:
    imports = load_imports(context_conf)
    if not imports:
        print(f"{DIM}no imports registered in {imports_conf_path_for(context_conf)}{RESET}")
        return
    broken = []
    for alias, target in imports.items():
        p = Path(target)
        if not p.exists():
            broken.append((alias, target))
            print(f"  {RED}✗{RESET} #{alias} -> {target}  {RED}(missing){RESET}")
        else:
            print(f"  {GREEN}✓{RESET} #{alias} -> {target}")
    if broken:
        for alias, _ in broken:
            del imports[alias]
        save_imports(context_conf, imports)
        ok(f"removed {len(broken)} broken import(s): {', '.join('#' + a for a, _ in broken)}")
    else:
        ok("all imports resolve correctly")


def cmd_config_remove(context_conf: Path, ref: str) -> None:
    imports = load_imports(context_conf)
    if ref.startswith("#"):
        key = ref[1:]
        if key not in imports:
            err(f"--config @remove: no alias #{key} in {imports_conf_path_for(context_conf)}")
        del imports[key]
        save_imports(context_conf, imports)
        ok(f"removed alias #{key}")
        return

    target = str(resolve_conf_target_readonly(ref))
    matched = [k for k, v in imports.items() if v == target]
    if not matched:
        err(f"--config @remove: no import matches {ref!r} (resolved to {target})")
    for k in matched:
        del imports[k]
    save_imports(context_conf, imports)
    ok(f"removed {', '.join('#' + m for m in matched)}")


# ── id ───────────────────────────────────────────────────────────────────────
# No hashing at all: file content/metadata is never read for this. Each entry just
# gets a random 12-char id assigned once at link-time, used purely as a short alias
# for --delete/--rename lookups alongside the full path.
ID_ALPHABET = string.hexdigits[:16]  # 0-9a-f


def make_id() -> str:
    return "".join(random.choices(ID_ALPHABET, k=12))


# ── helpers ──────────────────────────────────────────────────────────────────
def same_filesystem(a: Path, b: Path) -> bool:
    a_dev = a.stat().st_dev if a.exists() else a.parent.resolve().stat().st_dev
    b_dev = b.stat().st_dev if b.exists() else b.parent.resolve().stat().st_dev
    return a_dev == b_dev


def hardlink_tree(src: Path, dst: Path) -> None:
    if src.is_file():
        dst.parent.mkdir(parents=True, exist_ok=True)
        os.link(src, dst)
        return
    for sub in src.rglob("*"):
        rel = sub.relative_to(src)
        target = dst / rel
        if sub.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            os.link(sub, target)


def find_entry(entries: list, ref: str):
    """Resolve a hardlink path, bare name, or id to an entry."""
    looks_like_path = "/" in ref or os.sep in ref
    ref_abs = str(Path(ref).expanduser().resolve()) if looks_like_path else None
    for entry in entries:
        if ref_abs and entry["path"] == ref_abs:
            return entry
        if entry["path"] == ref:
            return entry
        if not looks_like_path and entry["name"] == ref:
            return entry
        if entry["id"] == ref:
            return entry
    return None


# ── commands ─────────────────────────────────────────────────────────────────
def _print_entries(entries: list) -> None:
    for entry in entries:
        path = Path(entry["path"])
        alive = path.exists()
        dot = f"{GREEN}●{RESET}" if alive else f"{RED}●{RESET}"
        print(f"  {dot}  {BOLD}{entry['name']}{RESET}")
        print(f"     id    {CYAN}{entry['id']}{RESET}")
        print(f"     path  {entry['path']}")
        print(f"     from  {entry['original']}")
        if not alive:
            print(f"     {RED}missing{RESET}")
        print()


def cmd_list(target: str | None) -> None:
    """No target: merge the active conf + every registered import, each
    under its own header. A target (alias/dir/*.json/@pwd) restricts the
    listing to just that one store."""
    if target is not None:
        resolved = resolve_config_arg_readonly(target, META_PATH)
        if resolved is None:
            err(f"--list: no alias matching {target!r}")
        entries = load_meta(resolved)
        if not entries:
            print(f"{DIM}no entries tracked in {resolved}{RESET}")
            return
        print(f"{BOLD}hardlinks in {resolved} ({len(entries)} tracked):{RESET}\n")
        _print_entries(entries)
        return

    stores = [("default", META_PATH)]
    for alias, raw in load_imports(META_PATH).items():
        stores.append((f"#{alias}", resolve_conf_target_readonly(raw)))

    any_entries = False
    for label, conf_path in stores:
        entries = load_meta(conf_path)
        if not entries:
            continue
        any_entries = True
        print(f"{BOLD}[{label}]{RESET}  {DIM}{conf_path}{RESET}  ({len(entries)} tracked)\n")
        _print_entries(entries)
    if not any_entries:
        print(f"{DIM}no entries tracked{RESET}")


def cmd_link(entries: list, original: str, link_location: str) -> None:
    src = Path(original).expanduser().resolve()
    if not src.exists():
        err(f"original does not exist: {src}")

    dst = Path(link_location).expanduser()
    if dst.exists() and dst.is_dir():
        dst = dst / src.name

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst = dst.parent.resolve() / dst.name

    if not same_filesystem(src, dst):
        err(
            "cannot create hardlink across partitions/drives "
            f"({src} and {dst.parent} are on different filesystems)"
        )

    if dst.exists():
        err(f"target already exists: {dst}")

    hardlink_tree(src, dst)
    entry_id = make_id()

    entries.append(
        {
            "name": dst.name,
            "path": str(dst),
            "original": str(src),
            "id": entry_id,
        }
    )
    save_meta(entries)
    ok(f"linked {src} -> {dst} [{entry_id}]")


def cmd_delete(entries: list, ref: str) -> None:
    entry = find_entry(entries, ref)
    if not entry:
        err(f"no entry matching: {ref}")

    path = Path(entry["path"])
    if path.exists():
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()

    entries.remove(entry)
    save_meta(entries)
    ok(f"deleted {entry['path']}")


def cmd_rename(entries: list, ref: str, new_path: str) -> None:
    entry = find_entry(entries, ref)
    if not entry:
        err(f"no entry matching: {ref}")

    cur = Path(entry["path"])
    if not cur.exists():
        err(f"hardlink path no longer exists: {cur}")

    new = Path(new_path).expanduser()
    if new_path and os.sep not in new_path and "/" not in new_path:
        # bare name -> keep current directory, just rename
        new = cur.parent / new_path

    if not same_filesystem(cur, new):
        err(
            "cannot move across partitions/drives "
            f"({cur} and {new.parent} are on different filesystems)"
        )

    new.parent.mkdir(parents=True, exist_ok=True)
    if new.exists():
        err(f"target already exists: {new}")

    cur.rename(new)
    entry["path"] = str(new)
    entry["name"] = new.name
    save_meta(entries)
    ok(f"renamed {cur} -> {new}")


def cmd_cleanup(entries: list) -> None:
    kept = []
    removed = 0
    for entry in entries:
        if Path(entry["path"]).exists():
            kept.append(entry)
        else:
            removed += 1

    save_meta(kept)
    if removed:
        ok(f"removed {removed} invalid entr{'y' if removed == 1 else 'ies'}, {len(kept)} remaining")
    else:
        ok(f"nothing to clean, {len(kept)} entries valid")


def cmd_install() -> None:
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    if BIN_LINK.is_symlink() or BIN_LINK.exists():
        if BIN_LINK.is_symlink() and BIN_LINK.resolve() == SCRIPT_PATH:
            ok(f"already installed: {BIN_LINK} -> {SCRIPT_PATH}")
            return
        err(f"{BIN_LINK} already exists and is not this script's symlink")
    SCRIPT_PATH.chmod(SCRIPT_PATH.stat().st_mode | 0o111)
    BIN_LINK.symlink_to(SCRIPT_PATH)
    ok(f"installed: {BIN_LINK} -> {SCRIPT_PATH}")


def cmd_uninstall() -> None:
    if not BIN_LINK.exists() and not BIN_LINK.is_symlink():
        ok(f"not installed: {BIN_LINK}")
        return
    if BIN_LINK.is_symlink() and BIN_LINK.resolve() != SCRIPT_PATH:
        err(f"{BIN_LINK} exists but does not point at this script, refusing to remove")
    BIN_LINK.unlink()
    ok(f"removed: {BIN_LINK}")


def print_help() -> None:
    print(f"{BOLD}hlm{RESET} — hardlink manager")
    print()
    print(f"{BOLD}USAGE{RESET}")
    print(f"  hlm --list  {YELLOW}[alias|dir|*.json]{RESET}")
    print(f"  hlm --link    {YELLOW}<original> <location>{RESET}")
    print(f"  hlm --delete  {YELLOW}<hardlink_path|id>{RESET}")
    print(f"  hlm --rename  {YELLOW}<hardlink_path|id> <new_path|bare_name>{RESET}")
    print(f"  hlm --cleanup")
    print(f"  hlm --install")
    print(f"  hlm --uninstall")
    print(f"  hlm --config  {YELLOW}<dir|*.json|@pwd>{RESET}              [command...]")
    print(f"  hlm --config  {YELLOW}#<alias>{RESET}                      [command...]")
    print(f"  hlm --config  {YELLOW}@import <dir|*.json|@pwd> <alias>{RESET}")
    print(f"  hlm --config  {YELLOW}@default <dir|*.json|@pwd>{RESET}")
    print(f"  hlm --config  {YELLOW}@verify{RESET}")
    print(f"  hlm --config  {YELLOW}@remove <#alias|dir|*.json>{RESET}")
    print()
    print(f"{BOLD}COMMANDS{RESET}")
    print(f"  {CYAN}--list{RESET}               with no argument: every store (default + every import),")
    print(f"                       each under its own header. With an argument: just that one store.")
    print(f"  {CYAN}--link{RESET}               hardlink <original> (file or dir) at <location>, tracked with a new id")
    print(f"  {CYAN}--delete{RESET}             remove a tracked hardlink (never touches the original)")
    print(f"  {CYAN}--rename{RESET}             move/rename a tracked hardlink in place")
    print(f"  {CYAN}--cleanup{RESET}            drop entries whose hardlink path no longer exists")
    print(f"  {CYAN}--install{RESET}            symlink this script to ~/.local/bin/hlm")
    print(f"  {CYAN}--uninstall{RESET}          remove that symlink")
    print(f"  {CYAN}--config{RESET}             pick/create which metadata store this invocation uses")
    print()
    print(f"{BOLD}--config{RESET}")
    print(f"  Can appear anywhere on the command line (before or after the main")
    print(f"  command, never inside another flag's own arguments). Lets multiple")
    print(f"  independent hardlink-tracking contexts exist side by side (e.g. one")
    print(f"  per media library) instead of always using one fixed metadata.json.")
    print()
    print(f"  {YELLOW}<dir>{RESET}        use/create <dir>/metadata.json")
    print(f"  {YELLOW}<path>.json{RESET}  use/create that exact file, any name")
    print(f"  {YELLOW}@pwd{RESET}         use/create metadata.json in the current directory")
    print(f"  {YELLOW}#<alias>{RESET}     use whatever a prior @import registered under that alias")
    print(f"  {YELLOW}@import <target> <alias>{RESET}   register <target> (same forms as above,")
    print(f"                              including #<alias>) under #<alias>, in")
    print(f"                              imports.json next to whichever conf is")
    print(f"                              active so far this run")
    print(f"  {YELLOW}@default <target>{RESET}          make <target> the conf used whenever")
    print(f"                              --config is omitted entirely, from now on")
    print(f"  {YELLOW}@verify{RESET}                    check every import still resolves to an")
    print(f"                              existing path; print + remove any that don't")
    print(f"  {YELLOW}@remove <ref>{RESET}               drop one import, by #alias or by the")
    print(f"                              dir/*.json/@pwd it was registered with")
    print()
    print(f"  Missing directories/files at any of the above are created automatically")
    print(f"  ({YELLOW}@verify{RESET}/{YELLOW}@remove{RESET}/plain {YELLOW}--list <target>{RESET} are read-only and never create anything).")
    print()
    print(f"{BOLD}NOTES{RESET}")
    print(f"  - real hardlinks only, never symlinks; refuses cross-filesystem links/renames")
    print(f"  - directories are mirrored with every file hardlinked individually")
    print(f"  - <hardlink_path|id> accepts the full path, the bare filename, or the id from --list")
    print(f"  - active metadata store for this run: {DIM}{META_PATH}{RESET}")


# ── cli ──────────────────────────────────────────────────────────────────────
def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print_help()
        return

    raw_argv, config_directives = consume_config_directives(sys.argv[1:])
    apply_config_directives(config_directives)

    if not raw_argv:
        # a bare `hlm --config ...` with no other command — directives (if
        # any) have already run; nothing else to do. Plain `hlm` with no
        # args at all (no directives either) just shows help, same as before.
        if not config_directives:
            print_help()
        return

    parser = argparse.ArgumentParser(prog="hlm", add_help=False)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--list", nargs="?", const="__ALL__", default=False,
                        metavar="alias|dir|*.json")
    group.add_argument("--link", nargs=2, metavar=("ORIGINAL", "LOCATION"))
    group.add_argument("--delete", nargs=1, metavar="HARDLINK")
    group.add_argument("--rename", nargs=2, metavar=("HARDLINK", "NEW_PATH"))
    group.add_argument("--cleanup", action="store_true")
    group.add_argument("--install", action="store_true")
    group.add_argument("--uninstall", action="store_true")

    args = parser.parse_args(raw_argv)

    if args.install:
        cmd_install()
        return
    if args.uninstall:
        cmd_uninstall()
        return

    if args.list is not False:
        cmd_list(None if args.list == "__ALL__" else args.list)
        return

    entries = load_meta()

    if args.link:
        cmd_link(entries, args.link[0], args.link[1])
    elif args.delete:
        cmd_delete(entries, args.delete[0])
    elif args.rename:
        cmd_rename(entries, args.rename[0], args.rename[1])
    elif args.cleanup:
        cmd_cleanup(entries)


if __name__ == "__main__":
    main()
