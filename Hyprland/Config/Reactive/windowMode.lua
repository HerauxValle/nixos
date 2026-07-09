-- MODE SWITCHER BETWEEN "DWINDLE" & "SCROLLING"
hl.bind(mainMod .. " + CTRL + T", hl.dsp.exec_cmd(SCRIPTS_DIR .. "/cycleMode.sh"))

-- ═══════════════════════════════════════════════════════════════
-- SHARED BINDS (ALWAYS ACTIVE)
-- ═══════════════════════════════════════════════════════════════

hl.bind(mainMod .. " + CTRL + SHIFT + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + CTRL + SHIFT + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + CTRL + SHIFT + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + CTRL + SHIFT + down",  hl.dsp.focus({ direction = "down" }))

hl.bind(mainMod .. " + CTRL + left",  hl.dsp.window.resize({ x = -20, y = 0,   relative = true }))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.resize({ x = 20,  y = 0,   relative = true }))
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.resize({ x = 0,   y = -20, relative = true }))
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.resize({ x = 0,   y = 20,  relative = true }))

hl.bind(mainMod .. " + ALT + W",   hl.dsp.workspace.toggle_special())
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mainMod .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
-- action = "toggle" is required -- without it hl.window.fullscreen defaults
-- to always setting fullscreen on, never unsetting it back.
hl.bind(mainMod .. " + F",       hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))

-- ALT + Tab is the scrolloverview trigger (Config/Binds/plugins.lua); kept
-- here only as reverse-cycle since it doesn't collide with that.
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ prev = true }))

hl.bind(mainMod .. " + D",        hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + CTRL + D", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + ALT + D",  hl.dsp.layout("togglesplit"))

hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ═══════════════════════════════════════════════════════════════
-- LAYOUT-SPECIFIC BINDS
-- ═══════════════════════════════════════════════════════════════

-- Dwindle >>
--& --- Dwindle layout ---
-- hl.bind(mainMod .. " + left",          hl.dsp.window.move({ direction = "left" }))
-- hl.bind(mainMod .. " + right",         hl.dsp.window.move({ direction = "right" }))
-- hl.bind(mainMod .. " + up",            hl.dsp.window.move({ direction = "up" }))
-- hl.bind(mainMod .. " + down",          hl.dsp.window.move({ direction = "down" }))
-- hl.bind(mainMod .. " + SHIFT + right", hl.dsp.focus({ workspace = "e+1" }))
-- hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.focus({ workspace = "e-1" }))
-- hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.focus({ workspace = "e+1" }))
-- hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.focus({ workspace = "e-1" }))
-- hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
-- hl.animation({ leaf = "workspaces", enabled = true, speed = 13, bezier = "easeOut", style = "slide" })
-- << END

-- Hyprscroll >>
--& --- Hyprscroll scrolling layout ---
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + ALT + left",    hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + ALT + right",   hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + ALT + up",      hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + ALT + down",    hl.dsp.window.move({ direction = "down" }))
hl.bind(mainMod .. " + left",  hl.dsp.window.swap({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.window.swap({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.window.swap({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.window.swap({ direction = "down" }))
hl.bind(mainMod .. " + SHIFT + up",        hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + SHIFT + down",       hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + ALT + up",   hl.dsp.window.move({ workspace = "e-1" }))
hl.bind(mainMod .. " + SHIFT + ALT + down", hl.dsp.window.move({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
-- old: hl.animation({ leaf = "workspaces", enabled = true, speed = 13, bezier = "easeOut", style = "slidevert" })
-- 3.5ds = 350ms -- upper end of Material's "medium" band (250-400ms), since
-- a full workspace swap covers more screen area than a single window move
-- and needs a touch longer to read clearly; "standard" curve from theme.lua
-- since it's a symmetric back-and-forth motion, not a one-way enter/exit.
hl.animation({ leaf = "workspaces", enabled = true, speed = 3.5, bezier = "standard", style = "slidevert" })
-- << END

hl.config({
    general = {
        layout = "scrolling",
    },
})
