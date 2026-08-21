#!/usr/bin/env python3
# &desc: "Exclude files from dotfiles backup snapshot -- gitignore-pattern matching via fnmatch, replaces old rm -rf loop, imported by preflight_check.py."
# Applies excludeFiles entries to a synced snapshot dir -- replaces what
# used to be a per-entry `rm -rf "$dir/$f"` loop, now gitignore-pattern-
# aware. See preflight_check.py, which imports find_matches from here
# directly (both are real standalone scripts, not concatenated text
# fragments, so a real Python import is exactly the right tool) for the
# "this excludeFiles entry matches nothing" activation-time warning --
# same matching engine, so a warning there and an actual removal here
# never disagree.
#
# An entry with none of *, ?, [ is treated as a plain literal path,
# relative to `dir` -- removed exactly like the old `rm -rf "$dir/$f"`
# it replaces, no matching engine involved at all, so every entry that
# predates gitignore-style pattern support behaves identically to
# before. An entry containing any of those characters is matched with
# Python's fnmatch against every path (file or directory) under `dir`,
# relative to `dir` with forward slashes -- the same engine
# git-filter-repo's own `glob:` entries use internally (confirmed by
# reading git_filter_repo.py: `fnmatch.fnmatch(pathname, path_exp)`),
# so a pattern behaves identically whether it's excluding the current
# snapshot here or being scrubbed from history there (see
# ../default.nix's excludePathsFileContent).
#
# One real difference from an actual .gitignore, worth knowing: fnmatch's
# `*` matches `/` too (it compiles to `.*`), so a single `*` already
# behaves like `**` would in a real .gitignore -- there's no need to
# write `**` for "any depth", though it's accepted (it just collapses to
# the same thing as `*`). No `!`-negation support -- this is an
# exclude-only list, there's nothing to un-exclude.
#
# <dir> <patterns-file> -- patterns-file is cfg.excludeFiles, one entry
# per line, written by ../default.nix.
import fnmatch
import os
import shutil
import sys
from pathlib import Path

GLOB_CHARS = ("*", "?", "[")


def is_glob(pattern):
    return any(c in pattern for c in GLOB_CHARS)


def find_matches(root, pattern):
    root = Path(root)
    if not is_glob(pattern):
        p = root / pattern
        return [p] if p.is_symlink() or p.exists() else []

    matches = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        kept = []
        for d in dirnames:
            relpath = d if rel_dir == "." else f"{rel_dir}/{d}"
            if fnmatch.fnmatch(relpath, pattern):
                matches.append(root / relpath)
            else:
                kept.append(d)
        dirnames[:] = kept  # don't descend into a directory we're about to remove
        for f in filenames:
            relpath = f if rel_dir == "." else f"{rel_dir}/{f}"
            if fnmatch.fnmatch(relpath, pattern):
                matches.append(root / relpath)
    return matches


def remove(path):
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
    elif path.is_dir():
        shutil.rmtree(path, ignore_errors=True)


def main():
    root, patterns_file = sys.argv[1], sys.argv[2]
    patterns = [p for p in Path(patterns_file).read_text().splitlines() if p]
    for pattern in patterns:
        for path in find_matches(root, pattern):
            remove(path)


if __name__ == "__main__":
    main()
