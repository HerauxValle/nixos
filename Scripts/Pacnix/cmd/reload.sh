#!/usr/bin/env bash
set -euo pipefail

# Reuses the real `reload` fish function and the real `qsr` command directly
# instead of duplicating their logic here -- each stays the single source of
# truth for its own behavior. Checks both exist before running either; if
# something's missing, warn and do nothing rather than half-run.

missing=""
if ! command -v fish >/dev/null 2>&1 || ! fish -c "functions -q reload" 2>/dev/null; then
    missing="${missing}  - fish \`reload\` function not found (fish missing, or no reload function defined)\n"
fi
if ! command -v qsr >/dev/null 2>&1; then
    missing="${missing}  - \`qsr\` not found on \$PATH\n"
fi
if ! command -v hyprctl >/dev/null 2>&1; then
    missing="${missing}  - \`hyprctl\` not found on \$PATH\n"
fi

if [ -n "$missing" ]; then
    printf 'warning: pacnix reload -- nothing run, missing:\n%b' "$missing" >&2
    exit 1
fi

fish -c reload
qsr
hyprctl reload

# Only meaningful from inside a kitty window (remote control connects via
# kitty's own child-process channel, not a general system-wide socket).
# Best-effort, silently: outside kitty it's a given this won't work, and a
# failure here shouldn't print noise over an otherwise-successful reload.
if [ -n "${KITTY_WINDOW_ID:-}" ]; then
    kitty @ load-config >/dev/null 2>&1 || true
fi
