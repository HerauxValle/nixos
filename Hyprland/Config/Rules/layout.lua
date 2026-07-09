-- --- WINDOWS AND WORKSPACES ---

-- See https://wiki.hypr.land/Configuring/Window-Rules/ for more
-- See https://wiki.hypr.land/Configuring/Workspace-Rules/ for workspace rules

-- old: this suppressed apps self-maximizing on launch, but it also blocks
-- the compositor's own internal maximize *state* from updating (not just
-- the client notification) -- confirmed live: mainMod+F would resize the
-- window bigger on first press (the raw geometry change goes through
-- regardless), but hl.get_active_window().fullscreen never actually flips
-- to 1, so a second press just re-applies "maximized" instead of undoing
-- it. Removed so mainMod+F's toggle (Config/Reactive/windowMode.lua)
-- actually works both directions. Re-add if some app's uninvited
-- self-maximize-on-launch becomes annoying again.
-- hl.window_rule({
--     name  = "suppress-maximize-events",
--     match = { class = ".*" },
--     suppress_event = "maximize",
-- })

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- Custom menu script
hl.window_rule({
    name  = "menu-float",
    match = { class = "menu-float" },

    float     = true,
    center    = true,
    size      = "800 600",
    animation = "slideIn bottom",
})
