#!/usr/bin/env bash
# &desc: "pacnix reload -- fish config reload, qsr, hyprctl config reload, and unload+reload every nix-built Hyprland plugin so code changes actually take effect"

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

# Nix-built Hyprland plugins (Nixos/modules/hyprland/plugins/) are loaded
# once at session start by Config/Apps/autostart.lua's own loop over this
# same directory. A rebuild only swaps the home-manager symlink to a new
# nix store path -- Hyprland already has the *old* .so dlopen'd in memory,
# so it never picks up the change until explicitly unloaded and reloaded.
# `hyprctl reload` above is a config reload only, not a plugin reload.
# Mirrors autostart.lua's loop, but unload-then-load instead of load-only;
# unload is allowed to fail (`|| true`) for a plugin not yet loaded (e.g.
# freshly added to the list, not loaded this session).
if command -v hyprctl >/dev/null 2>&1; then
    for f in "$HOME"/.local/share/hypr-plugins/*.so; do
        [ -e "$f" ] || continue
        hyprctl plugin unload "$f" >/dev/null 2>&1 || true
        hyprctl plugin load "$f"
    done
fi

# Only meaningful from inside a kitty window (remote control connects via
# kitty's own child-process channel, not a general system-wide socket).
# Best-effort, silently: outside kitty it's a given this won't work, and a
# failure here shouldn't print noise over an otherwise-successful reload.
if [ -n "${KITTY_WINDOW_ID:-}" ]; then
    kitty @ load-config >/dev/null 2>&1 || true
fi
