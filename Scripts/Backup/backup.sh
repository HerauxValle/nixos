#!/usr/bin/env bash
# backup.sh -- snapshot/restore live app config files that can't be
# Nix-managed directly (the app itself writes to them during normal use --
# e.g. VSCode's Settings UI, Dolphin's view-state -- so a read-only Nix
# symlink would break them). This is a plain manual copy, not a live link:
# `backup.sh` copies FROM the real path INTO Dotfiles/Backup/<key>;
# `backup.sh --restore` copies FROM Dotfiles/Backup/<key> back TO the real
# path. Add/remove entries in the BACKUPS array below.
#
# Must be run from this file's actual location in the Dotfiles checkout
# (e.g. `bash ~/Dotfiles/Scripts/Backup/backup.sh`), not the
# ~/.config/scripts symlinked copy -- that resolves into the read-only Nix
# store, where BACKUP_DIR below would neither exist nor be writable.
#
# Content-hash based: anything (file or whole directory) whose hash matches
# the last run is skipped untouched; a changed directory is stepped into
# one child at a time instead of being copied wholesale, so only what
# actually changed gets re-copied.

set -euo pipefail

DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
BACKUP_DIR="$DIR/../../Backup"   # Scripts/Backup/ -> Dotfiles/Backup

# Pure performance cache (skip re-copying unchanged content) -- not state,
# not config, so ~/.cache is the right place, not Dotfiles/Backup itself.
HASH_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-backup/hashes"

# key = name under Backup/, value = real, live path being backed up/restored
declare -A BACKUPS=(
    ["dolphinrc"]="$HOME/.config/dolphinrc"
    ["vscode-settings.json"]="$HOME/.config/Code/User/settings.json"

    # run.sh's frecency scores + alias DB -- pure runtime state, not
    # Nix/Dotfiles-tracked at all (see Scripts/Run/run.sh).
    ["lookup-db"]="${XDG_DATA_HOME:-$HOME/.local/share}/lookup/db"
    ["lookup-aliases"]="${XDG_DATA_HOME:-$HOME/.local/share}/lookup/aliases"

    # MyBar's config: theme.env is saved UI state (auto-written by
    # BarConfig._schedSave()), custom/ is the user's own override files --
    # both described in Quickshell/MyBar/README.md. state/pkgs.json is
    # deliberately not included: that's install.sh's own internal
    # bookkeeping, not user config.
    ["mybar-theme.env"]="$HOME/.config/mybar/theme.env"
    ["mybar-custom"]="$HOME/.config/mybar/custom"
)

# A file's hash is just its content hash. A directory's hash is the combined
# hash of all its files' contents (sorted by relative path first, so it's
# stable regardless of directory-listing order) -- so any change anywhere
# inside changes the directory's hash too.
_hash_of() {
    local path="$1"
    if [ -d "$path" ]; then
        find "$path" -type f -print0 2>/dev/null \
            | sort -z \
            | xargs -0 -r sha256sum 2>/dev/null \
            | sha256sum | cut -d' ' -f1
    else
        sha256sum "$path" 2>/dev/null | cut -d' ' -f1
    fi
}

# NUL-delimited (hash, path) pairs, not TSV/JSON -- a path can legally
# contain a literal tab or newline (rare, but real), which would corrupt
# a tab/newline-delimited format. NUL can't appear in a path at all (Unix
# paths are NUL-terminated C strings), so it's the one separator that
# never needs escaping. jq isn't guaranteed installed either way.
_cached_hash() {
    [ -f "$HASH_CACHE" ] || { printf ''; return; }
    local -a entries
    mapfile -d '' entries < "$HASH_CACHE"
    local i
    for (( i = 0; i < ${#entries[@]}; i += 2 )); do
        if [ "${entries[i+1]}" = "$1" ]; then
            printf '%s' "${entries[i]}"
            return
        fi
    done
    printf ''
}

_set_cached_hash() {
    local path="$1" hash="$2"
    mkdir -p "$(dirname "$HASH_CACHE")"
    touch "$HASH_CACHE"
    local -a entries
    mapfile -d '' entries < "$HASH_CACHE"
    local tmp; tmp=$(mktemp)
    local i
    for (( i = 0; i < ${#entries[@]}; i += 2 )); do
        [ "${entries[i+1]}" = "$path" ] && continue   # dropped, re-added below
        printf '%s\0%s\0' "${entries[i]}" "${entries[i+1]}" >> "$tmp"
    done
    printf '%s\0%s\0' "$hash" "$path" >> "$tmp"
    mv "$tmp" "$HASH_CACHE"
}

# sync SRC DEST -- SRC is always the read side (live path when backing up,
# Backup/<key> when restoring), DEST the write side. A path (file or dir)
# whose hash matches what was cached the last time IT was read as a source
# is skipped entirely, no recursion. A changed directory is stepped into,
# one child at a time, each deciding independently; a changed file is
# copied. The cache key is SRC's own absolute path, so backup and restore
# runs never collide with each other's cached hashes.
_sync() {
    local src="$1" dest="$2"
    [ -e "$src" ] || return 0

    local hash cached
    hash="$(_hash_of "$src")"
    cached="$(_cached_hash "$src")"

    if [ -n "$hash" ] && [ "$hash" = "$cached" ]; then
        return 0
    fi

    if [ -d "$src" ]; then
        mkdir -p "$dest"
        local child name
        for child in "$src"/* "$src"/.[!.]*; do
            [ -e "$child" ] || continue
            name="$(basename "$child")"
            _sync "$child" "$dest/$name"
        done
    else
        mkdir -p "$(dirname "$dest")"
        cp -a "$src" "$dest"
        echo "  $src"
    fi

    _set_cached_hash "$src" "$hash"
}

mode="${1:-}"

case "$mode" in
    --restore)
        for key in "${!BACKUPS[@]}"; do
            target="${BACKUPS[$key]}"
            src="$BACKUP_DIR/$key"
            if [ -e "$src" ]; then
                echo "restoring: $key -> $target"
                _sync "$src" "$target"
            else
                echo "no backup found for '$key' ($src), skipping" >&2
            fi
        done
        ;;
    "")
        mkdir -p "$BACKUP_DIR"
        for key in "${!BACKUPS[@]}"; do
            target="${BACKUPS[$key]}"
            dest="$BACKUP_DIR/$key"
            if [ -e "$target" ]; then
                echo "backing up: $key <- $target"
                _sync "$target" "$dest"
            else
                echo "source not found for '$key' ($target), skipping" >&2
            fi
        done
        ;;
    *)
        echo "usage: backup.sh [--restore]" >&2
        exit 1
        ;;
esac
