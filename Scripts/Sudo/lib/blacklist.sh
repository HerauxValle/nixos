#!/usr/bin/env bash
# lib/blacklist.sh -- manage the auto-mode command blacklist.

# Same shape as run.sh's own DB (~/.local/share/lookup/): live, user-editable
# state belongs in $XDG_DATA_HOME, not alongside the Nix-managed script
# itself (which is read-only wherever it's deployed read-only). The
# Dotfiles copy (lib/blacklist.conf, deployed alongside this file) is only
# ever read once, as the seed for a fresh install -- after that this is the
# one true copy, add/rem/edit write here directly, no env var needed.
BLACKLIST_FILE="${SUDO_BROKER_BLACKLIST_FILE:-${XDG_DATA_HOME:-$HOME/.local/share}/sudo-broker/blacklist.conf}"
if [[ ! -f "$BLACKLIST_FILE" ]]; then
    mkdir -p "$(dirname "$BLACKLIST_FILE")"
    cp "$SCRIPT_DIR/lib/blacklist.conf" "$BLACKLIST_FILE"
fi

# Returns 0 (blocked) if CMD starts with any blacklist pattern.
# Prints the matching pattern to stdout.
blacklist_check() {
    local cmd="$*"
    [[ -f "$BLACKLIST_FILE" ]] || return 1
    local pattern
    while IFS= read -r pattern; do
        # Skip blank lines and comments
        [[ -z "$pattern" || "$pattern" == '#'* ]] && continue
        # Block if command starts with pattern (with or without trailing space)
        if [[ "$cmd" == "$pattern" || "$cmd" == "$pattern "* ]]; then
            printf '%s\n' "$pattern"
            return 0
        fi
    done < "$BLACKLIST_FILE"
    return 1
}

do_blacklist_add() {
    local pattern="${*:-}"
    if [[ -z "$pattern" ]]; then
        echo "Usage: sudo --adv:blacklist-add <pattern>" >&2
        return 1
    fi
    if grep -qxF "$pattern" "$BLACKLIST_FILE" 2>/dev/null; then
        echo "Already blacklisted: $pattern"
        return 0
    fi
    printf '%s\n' "$pattern" >> "$BLACKLIST_FILE"
    echo "Blacklisted: $pattern"
}

do_blacklist_rem() {
    local pattern="${*:-}"
    if [[ -z "$pattern" ]]; then
        echo "Usage: sudo --adv:blacklist-rem <pattern>" >&2
        return 1
    fi
    if ! grep -qxF "$pattern" "$BLACKLIST_FILE" 2>/dev/null; then
        echo "Not in blacklist: $pattern" >&2
        return 1
    fi
    # Use a temp file to avoid in-place sed portability issues
    local tmp
    tmp=$(mktemp)
    grep -vxF "$pattern" "$BLACKLIST_FILE" > "$tmp"
    mv "$tmp" "$BLACKLIST_FILE"
    echo "Removed: $pattern"
}

do_blacklist_list() {
    if [[ ! -f "$BLACKLIST_FILE" ]]; then
        echo "No blacklist file found at: $BLACKLIST_FILE" >&2
        return 1
    fi
    local count=0 pattern
    echo "Blacklisted patterns (${BLACKLIST_FILE}):"
    echo ""
    while IFS= read -r pattern; do
        [[ -z "$pattern" || "$pattern" == '#'* ]] && continue
        printf '  %s\n' "$pattern"
        (( count++ )) || true
    done < "$BLACKLIST_FILE"
    echo ""
    echo "  Total: $count pattern(s)"
}

do_blacklist_edit() {
    local editor
    # Prefer terminal editors; fall back to $VISUAL / $EDITOR / common editors
    for candidate in "$VISUAL" "$EDITOR" nano vim vi micro; do
        [[ -z "$candidate" ]] && continue
        if command -v "$candidate" &>/dev/null; then
            editor="$candidate"
            break
        fi
    done
    if [[ -z "${editor:-}" ]]; then
        echo "No editor found. Set \$EDITOR or install nano/vim." >&2
        return 1
    fi
    "$editor" "$BLACKLIST_FILE"
}
