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

-- old (both variants confirmed broken specifically under scrolling layout --
-- native maximize resizes the window on the first press but the
-- compositor's internal fullscreen state never registers it, so neither a
-- second native toggle nor a manual state re-check can tell it needs to
-- unset anything. The exact same dispatcher toggles correctly under
-- dwindle/master, which is why the replacement below only kicks in when
-- scrolling is the active layout and defers to the native one otherwise):
-- hl.bind(mainMod .. " + F", function()
--     local win = hl.get_active_window()
--     if not win then return end
--     local action = (win.fullscreen == 1) and "unset" or "set"
--     hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = action, window = "address:" .. win.address }))
-- end)
-- hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))

-- old (hl.bind(keys, function() ... end) confirmed dead on a real keypress
-- -- registered with no errors, but zero effect, while the exact same
-- logic worked every time invoked manually via hyprctl eval. Moved to
-- Scripts/scrollMaximize.sh, bound via exec_cmd below, since
-- dispatcher-style binds are proven to fire and that's the same pattern
-- FWM.sh/cycleMode.sh/hyprfloat already use elsewhere in this repo for
-- stateful toggles):
-- local maximizedWidths = {}
-- hl.bind(mainMod .. " + F", function()
--     if hl.get_config("general.layout") ~= "scrolling" then
--         hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
--         return
--     end
--     local win = hl.get_active_window()
--     if not win then return end
--     local target = "address:" .. win.address
--     local savedWidth = maximizedWidths[win.address]
--     if savedWidth then
--         hl.dispatch(hl.dsp.window.resize({ x = savedWidth, y = win.size.y, relative = false, window = target }))
--         maximizedWidths[win.address] = nil
--         return
--     end
--     maximizedWidths[win.address] = win.size.x
--     local gapsOut = hl.get_config("general.gaps_out") or 0
--     local gapLeft  = type(gapsOut) == "table" and (gapsOut.left  or 0) or gapsOut
--     local gapRight = type(gapsOut) == "table" and (gapsOut.right or 0) or gapsOut
--     hl.dispatch(hl.dsp.window.resize({ x = win.monitor.width - gapLeft - gapRight, y = win.size.y, relative = false, window = target }))
-- end)

-- See Scripts/scrollMaximize.sh for the maximize-toggle logic and why it
-- lives in a script instead of inline Lua.
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(SCRIPTS_DIR .. "/scrollMaximize.sh"))

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
-- Workspace focus/move next/prev binds live entirely in MyBar's own
-- configurable-keybind system now (config/BarConfig.qml's bindWorkspace*
-- properties, registered via "qs ipc call" the same way drawer/launcher/etc.
-- already are) -- not here, so they show up on the Binds settings page under
-- WORKSPACES instead of being fixed. See shell.qml's IpcHandlers for the
-- actual dispatch + BarConfig.invertWorkspaceIds direction flip.
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
-- old: hl.animation({ leaf = "workspaces", enabled = true, speed = 13, bezier = "easeOut", style = "slidevert" })
-- old: hl.animation({ leaf = "workspaces", enabled = true, speed = 3.5, bezier = "standard", style = "slidevert" })
-- old: hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "standard", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "standard", style = "slidevert" })
-- << END

hl.config({
    general = {
        layout = "scrolling",
    },
})
