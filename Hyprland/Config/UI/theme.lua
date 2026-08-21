-- --- Looks and Feel ---

hl.config({
    general = {
        gaps_in  = 14,
        gaps_out = 28,

        border_size = 2,

        col = {
            active_border   = "rgba(1E201Eee)",
            inactive_border = "rgba(595959aa)",
        },

        resize_on_border = true,

        allow_tearing = true,
    },

    decoration = {
        rounding       = 12,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,

            -- green: 1a1a1aee, blue: ffffffee
            color = "rgba(ffffffee)",
        },

        -- https://wiki.hypr.land/Configuring/Variables/#blur
        blur = {
            enabled  = true,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },
})

-- https://wiki.hypr.land/Configuring/Variables/#animations
hl.config({
    animations = {
        enabled = true,
    },
})

-- old: hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
-- old: hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
-- old: hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
-- old: hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
-- old: hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
-- old: hl.curve("easeOut",        { type = "bezier", points = { {0.16, 1},    {0.9, 1}     } })

-- Material Design 3 motion curves -- these are the published, user-tested
-- tokens from Google's motion system (m3.material.io/styles/motion), not
-- hand-picked control points. "standard" is for symmetric/utility motion,
-- the decelerate/accelerate pairs are for elements entering/exiting (an
-- entering element should decelerate into place, an exiting one should
-- accelerate away -- mirrors real-world inertia, which is why it reads as
-- natural rather than mechanical).
hl.curve("standard",              { type = "bezier", points = { {0.2, 0},    {0, 1}    } })
hl.curve("standardDecelerate",    { type = "bezier", points = { {0, 0},      {0, 1}    } })
hl.curve("standardAccelerate",    { type = "bezier", points = { {0.3, 0},    {1, 1}    } })
hl.curve("emphasizedDecelerate",  { type = "bezier", points = { {0.05, 0.7}, {0.1, 1}  } })
hl.curve("emphasizedAccelerate",  { type = "bezier", points = { {0.3, 0},    {0.8, 0.15} } })

-- old: hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
-- old: hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
-- old: hl.animation({ leaf = "windows",       enabled = true, speed = 7,    bezier = "easeOutQuint" })
-- old: hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
-- old: hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
-- old: hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
-- old: hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
-- old: hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
-- old: hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
-- old: hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
-- old: hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
-- old: hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
-- old: hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
-- old: hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7, bezier = "quick" })
-- old (still relocated below): hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
-- old (still relocated below): hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
-- old (still relocated below): hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
-- Relocated to reactive/windowMode.lua: hl.animation({ leaf = "workspaces", enabled = true, speed = 13, bezier = "easeOut", style = "slide" })

-- Durations follow Material Design 3's duration tokens (in deciseconds --
-- Hyprland's speed unit is 1ds = 100ms, per wiki.hypr.land/.../Animations).
-- "Short" (100-200ms) is for small/utility motion (borders, fades) that
-- fires often and must never feel laggy. "Medium" (250-400ms) is for
-- larger spatial motion (a window actually moving/resizing) -- long enough
-- to read clearly as motion, short of Nielsen's ~1s threshold where users
-- start perceiving lag. Exits consistently get a shorter duration than
-- their matching entrance (M3's own guidance: get out of the way faster
-- than you arrived).
hl.animation({ leaf = "global",        enabled = true, speed = 3,   bezier = "standard" })
hl.animation({ leaf = "border",        enabled = true, speed = 1.5, bezier = "standard" })
hl.animation({ leaf = "windows",       enabled = true, speed = 3,   bezier = "standard" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 2.5, bezier = "emphasizedDecelerate", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 2,   bezier = "emphasizedAccelerate",  style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.5, bezier = "standardDecelerate" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1,   bezier = "standardAccelerate" })
hl.animation({ leaf = "fade",          enabled = true, speed = 2,   bezier = "standard" })
hl.animation({ leaf = "layers",        enabled = true, speed = 2,   bezier = "standard" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 1.5, bezier = "standardDecelerate", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1,   bezier = "standardAccelerate",  style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.5, bezier = "standardDecelerate" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1,   bezier = "standardAccelerate" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 3.5, bezier = "standard" })

-- Ref https://wiki.hypr.land/Configuring/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

-- See https://wiki.hypr.land/Configuring/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        preserve_split = true,
    },
})

-- See https://wiki.hypr.land/Configuring/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- https://wiki.hypr.land/Configuring/Variables/#misc
hl.config({
    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
    },
})
