#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages(ps: [ps.pyyaml])" -p rsync -p lsof

# Moves a Bottles bottle's real data from one location to another (e.g. out
# of ~/.local/share/bottles/bottles into a custom folder like
# ~/Applications/Bottles/<name>, or back again) the same way it's done by
# hand: rsync the data over, fix every absolute path baked into bottle.yml
# (External_Programs entries, Path itself), flip Custom_Path to match
# whether the new location is still the default bottles root or not, update
# any *.desktop launcher and library.yml entries that point at the old
# path, and only then delete the old copy -- never before the new one is
# verified in place. Stops any live wine/bottle process using the bottle
# first (with confirmation), since moving files out from under a running
# wineserver/game corrupts them.
#
# Two more modes cover the "restored the dotfiles/data on a fresh install
# but the Bottles registry itself never came along" case -- Bottles only
# ever discovers a bottle via ~/.local/share/bottles/bottles (a real
# bottle.yml sitting directly there, or a placeholder.yml redirecting
# elsewhere); real bottle data sitting anywhere else (e.g. a custom
# ~/Applications/Bottles/<name> synced back by a backup) is otherwise
# completely invisible to it, silently, with no error:
#
#   migrate.py adopt <path>        -- register one already-in-place bottle
#   migrate.py adopt-all [<dir>]   -- register every bottle folder found
#                                      directly under <dir> (default
#                                      ~/Applications/Bottles) that isn't
#                                      already registered
#
# Neither mode copies, moves, or deletes any bottle data -- they only
# write/repair the registry placeholder and the bottle's own
# Custom_Path/Path fields to match where it already lives.

import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

import yaml

BOTTLES_ROOT = Path.home() / ".local/share/bottles/bottles"
APPLICATIONS_DIR = Path.home() / ".local/share/applications"
LIBRARY_YML = Path.home() / ".local/share/bottles/library.yml"


def die(msg):
    print(f"[x] {msg}", file=sys.stderr)
    sys.exit(1)


def ask(prompt):
    try:
        return input(prompt).strip()
    except (EOFError, KeyboardInterrupt):
        print()
        die("aborted")


def confirm(prompt):
    return ask(prompt).lower() in ("y", "yes")


def du_bytes(path: Path) -> int:
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            fp = os.path.join(root, f)
            try:
                total += os.path.getsize(fp)
            except OSError:
                pass
    return total


def find_registered_name_or_none(path: Path):
    """The folder name under BOTTLES_ROOT that identifies this bottle to
    Bottles, if it's actually registered -- either path's own name (it IS
    the default-location registry slot and holds a real bottle.yml), or
    whichever registry slot's placeholder.yml points at path. None if
    Bottles has no registry entry for it at all."""
    if path.parent == BOTTLES_ROOT:
        return path.name if (path / "bottle.yml").exists() else None
    for entry in BOTTLES_ROOT.iterdir():
        placeholder = entry / "placeholder.yml"
        if not placeholder.exists():
            continue
        try:
            data = yaml.safe_load(placeholder.read_text()) or {}
        except yaml.YAMLError:
            continue
        target = data.get("Path")
        if target and Path(os.path.expanduser(target)).resolve() == path:
            return entry.name
    return None


def find_registry_name(old_path: Path) -> str:
    name = find_registered_name_or_none(old_path)
    if name is None:
        die(
            f"could not find a Bottles registry entry pointing at {old_path} -- "
            "is this really the bottle's current real location? (a bottle that "
            "exists on disk but was never registered needs 'migrate.py adopt' "
            "instead, not a migration)"
        )
    return name


def load_config(bottle_path: Path) -> dict:
    cfg_file = bottle_path / "bottle.yml"
    if not cfg_file.exists():
        die(f"{cfg_file} not found -- is {bottle_path} really a bottle?")
    with open(cfg_file) as f:
        return yaml.safe_load(f)


def save_config(bottle_path: Path, cfg: dict):
    with open(bottle_path / "bottle.yml", "w") as f:
        yaml.safe_dump(cfg, f, default_flow_style=False, allow_unicode=True)


def replace_paths(obj, old: str, new: str):
    """Recursively swap `old` for `new` in every string value of a loaded
    YAML structure -- covers External_Programs' folder/path/icon fields
    plus anything else that happened to bake in the absolute path."""
    if isinstance(obj, dict):
        return {k: replace_paths(v, old, new) for k, v in obj.items()}
    if isinstance(obj, list):
        return [replace_paths(v, old, new) for v in obj]
    if isinstance(obj, str) and old in obj:
        return obj.replace(old, new)
    return obj


def update_desktop_files(old: str, new: str):
    changed = []
    if not APPLICATIONS_DIR.is_dir():
        return changed
    for f in APPLICATIONS_DIR.glob("bottles-*.desktop"):
        text = f.read_text()
        if old in text:
            f.write_text(text.replace(old, new))
            changed.append(f.name)
    return changed


def update_library_yml(old: str, new: str) -> bool:
    if not LIBRARY_YML.exists():
        return False
    with open(LIBRARY_YML) as f:
        data = yaml.safe_load(f) or {}
    updated = replace_paths(data, old, new)
    if updated == data:
        return False
    with open(LIBRARY_YML, "w") as f:
        yaml.safe_dump(updated, f, default_flow_style=False, allow_unicode=True)
    return True


def running_pids_for(bottle_path: Path):
    """Every process (our own user's -- that's all /proc/*/environ lets us
    read anyway) whose WINEPREFIX points at this bottle."""
    pids = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            raw = (proc / "environ").read_bytes()
        except (PermissionError, FileNotFoundError, ProcessLookupError):
            continue
        env = dict(e.split(b"=", 1) for e in raw.split(b"\0") if b"=" in e)
        wineprefix = env.get(b"WINEPREFIX")
        if not wineprefix:
            continue
        try:
            if Path(os.fsdecode(wineprefix)).resolve() == bottle_path:
                pids.append(proc.name)
        except OSError:
            continue
    return pids


def find_wineserver(bottle_path: Path) -> str:
    cfg = load_config(bottle_path)
    runner = cfg.get("Runner", "")
    candidate = Path.home() / ".local/share/bottles/runners" / runner / "bin/wineserver"
    if candidate.exists():
        return str(candidate)
    return shutil.which("wineserver") or "wineserver"


def stop_bottle_processes(bottle_path: Path, name: str):
    pids = running_pids_for(bottle_path)
    if not pids:
        return
    print(f"[!] '{name}' has live processes using it right now (PIDs: {', '.join(pids)})")
    if not confirm("    stop them now before migrating? [y/N] "):
        die("aborted -- close the bottle's processes yourself and re-run")

    ws = find_wineserver(bottle_path)
    env = os.environ.copy()
    env["WINEPREFIX"] = str(bottle_path)
    subprocess.run([ws, "-k"], env=env, check=False)
    time.sleep(2)

    pids = running_pids_for(bottle_path)
    if pids:
        print(f"    [!] still running after wineserver -k (PIDs: {', '.join(pids)}) -- sending SIGTERM")
        for pid in pids:
            try:
                os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(2)
        pids = running_pids_for(bottle_path)

    if pids:
        die(f"could not stop everything (still running: {', '.join(pids)}) -- close it manually and re-run")
    print("    [✓] stopped")


def check_no_open_files(bottle_path: Path):
    lsof = shutil.which("lsof")
    if not lsof:
        return
    out = subprocess.run([lsof, "+D", str(bottle_path)], capture_output=True, text=True)
    if out.stdout.strip():
        die(f"processes still have files open under {bottle_path} -- close them and re-run:\n{out.stdout}")


def adopt_one(path: Path, strict: bool = True) -> bool:
    """Register an already-in-place bottle folder with Bottles (write/
    repair its registry placeholder and Custom_Path/Path fields) without
    copying, moving, or deleting any data. Returns True if it registered
    something new, False if there was nothing to do (already registered)
    or -- only when strict=False, for adopt-all -- a conflict was skipped
    rather than aborting the whole batch."""
    if not (path / "bottle.yml").exists():
        msg = f"{path}/bottle.yml not found -- is this really a bottle's data folder?"
        if strict:
            die(msg)
        print(f"[!] skipping {path}: {msg}")
        return False

    existing = find_registered_name_or_none(path)
    if existing:
        print(f"[i] '{existing}' already registered and pointing here -- nothing to do")
        return False

    name = path.name
    default_location = path.parent == BOTTLES_ROOT
    registry_slot = BOTTLES_ROOT / name

    if not default_location and registry_slot.exists():
        msg = (
            f"registry slot {registry_slot} already exists and isn't a placeholder "
            f"pointing at {path} -- rename the folder or resolve the clash first"
        )
        if strict:
            die(msg)
        print(f"[!] skipping {path.name}: {msg}")
        return False

    cfg = load_config(path)
    cfg["Custom_Path"] = not default_location
    cfg["Path"] = name if default_location else str(path)
    save_config(path, cfg)

    if not default_location:
        registry_slot.mkdir(parents=True, exist_ok=True)
        (registry_slot / "placeholder.yml").write_text(f"Path: {path}\n")

    print(f"[✓] adopted '{name}' at {path}")
    return True


def adopt_all(base: Path):
    if not base.is_dir():
        die(f"{base} does not exist or is not a directory")
    candidates = sorted(e for e in base.iterdir() if e.is_dir() and (e / "bottle.yml").exists())
    if not candidates:
        print(f"[i] no bottle folders (containing bottle.yml) found directly under {base}")
        return
    adopted = sum(adopt_one(entry, strict=False) for entry in candidates)
    print(f"[✓] adopt-all finished: {adopted}/{len(candidates)} bottle(s) newly registered")


def main():
    args = sys.argv[1:]

    if args and args[0] in ("-h", "--help"):
        print(__doc__ or "")
        print("usage:")
        print("  migrate.py                       interactive: move a bottle")
        print("  migrate.py <old> <new>            move a bottle non-interactively")
        print("  migrate.py adopt [<path>]         register an already-in-place bottle")
        print("  migrate.py adopt-all [<dir>]      register every unregistered bottle under <dir>")
        print("                                    (default: ~/Applications/Bottles)")
        return

    if args and args[0] == "adopt":
        print("=== Bottles adopt ===")
        path_in = args[1] if len(args) >= 2 else ask(
            "bottle folder to register (contains bottle.yml; nothing will be copied/moved): "
        )
        if not path_in:
            die("a path is required")
        path = Path(os.path.expanduser(path_in)).resolve()
        if not path.is_dir():
            die(f"{path} does not exist or is not a directory")
        adopt_one(path)
        return

    if args and args[0] == "adopt-all":
        base_in = args[1] if len(args) >= 2 else str(Path.home() / "Applications/Bottles")
        base = Path(os.path.expanduser(base_in)).resolve()
        print(f"=== Bottles adopt-all: scanning {base} ===")
        adopt_all(base)
        return

    print("=== Bottles migration ===")
    if len(args) == 2:
        old_in, new_in = args
    else:
        old_in = ask("old bottle location (current real path): ")
        new_in = ask("new bottle location (where to move it to): ")
    if not old_in or not new_in:
        die("both paths are required")

    old_path = Path(os.path.expanduser(old_in)).resolve()
    new_path = Path(os.path.expanduser(new_in)).resolve()

    if not old_path.is_dir():
        die(f"{old_path} does not exist or is not a directory")
    if old_path == new_path:
        die("old and new paths are identical")
    if not (old_path / "bottle.yml").exists():
        die(f"{old_path}/bottle.yml not found -- is this really a bottle's data folder?")

    # Identify the bottle (by its registry placeholder if it has one)
    # before anything below possibly touches that same placeholder.
    name = find_registry_name(old_path)

    if new_path.exists():
        contents = list(new_path.iterdir())
        # moving back into the default bottles root: the registry slot
        # already exists holding nothing but its old placeholder.yml --
        # clear that one file so rsync can populate the directory cleanly.
        if contents == [new_path / "placeholder.yml"]:
            (new_path / "placeholder.yml").unlink()
        elif contents:
            die(f"{new_path} already exists and is not empty -- refusing to overwrite")
    default_location = new_path.parent == BOTTLES_ROOT
    print(f"[i] bottle identified as '{name}'")
    print(f"[i] {old_path}  ->  {new_path}")
    print(f"[i] destination is {'the default bottles location' if default_location else 'a custom location'}")

    if not confirm("proceed? [y/N] "):
        die("aborted")

    stop_bottle_processes(old_path, name)
    check_no_open_files(old_path)

    new_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"[cas] rsyncing '{old_path}' -> '{new_path}' ...")
    rsync = shutil.which("rsync")
    if not rsync:
        die("rsync not found")
    result = subprocess.run([rsync, "-aHAX", "--info=progress2", f"{old_path}/", f"{new_path}/"])
    if result.returncode != 0:
        die(f"rsync failed (exit {result.returncode}) -- old data left untouched, nothing deleted")

    old_size = du_bytes(old_path)
    new_size = du_bytes(new_path)
    if new_size < old_size:
        die(
            f"copy looks incomplete ({new_size} bytes at destination vs {old_size} bytes at source) "
            "-- not touching the original, check manually"
        )
    print(f"    [✓] copy verified ({new_size} bytes)")

    old_str, new_str = str(old_path), str(new_path)

    cfg = load_config(new_path)
    cfg = replace_paths(cfg, old_str, new_str)
    cfg["Custom_Path"] = not default_location
    cfg["Path"] = name if default_location else new_str
    save_config(new_path, cfg)
    print("    [✓] bottle.yml paths + Custom_Path updated")

    changed_desktop = update_desktop_files(old_str, new_str)
    if changed_desktop:
        print(f"    [✓] updated desktop files: {', '.join(changed_desktop)}")

    if update_library_yml(old_str, new_str):
        print("    [✓] library.yml updated")

    registry_slot = BOTTLES_ROOT / name
    if not default_location:
        registry_slot.mkdir(parents=True, exist_ok=True)
        (registry_slot / "placeholder.yml").write_text(f"Path: {new_str}\n")
        print(f"    [✓] placeholder written at {registry_slot}")

    if old_path == registry_slot:
        # old data lived directly in the registry slot -- clear it back
        # down to just the placeholder (or nothing, if the new location
        # is itself the default one, in which case old_path == new_path
        # can't happen since that's rejected above).
        for child in old_path.iterdir():
            if child.name == "placeholder.yml":
                continue
            if child.is_dir() and not child.is_symlink():
                shutil.rmtree(child)
            else:
                child.unlink()
        print(f"    [✓] cleared old registry slot at {old_path}")
    else:
        shutil.rmtree(old_path)
        print(f"    [✓] deleted old location {old_path}")

    print(f"[✓] '{name}' migrated to {new_path}")
    print("    restart Bottles for it to pick up the change")


if __name__ == "__main__":
    main()
