-- --- Workspace Switching ---

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + CTRL + SHIFT + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + CTRL + SHIFT + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + CTRL + SHIFT + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + CTRL + SHIFT + down",  hl.dsp.focus({ direction = "down" }))

-- Resize windows
hl.bind(mainMod .. " + CTRL + left",  hl.dsp.window.resize({ x = -20, y = 0,   relative = true }))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.resize({ x = 20,  y = 0,   relative = true }))
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.resize({ x = 0,   y = -20, relative = true }))
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.resize({ x = 0,   y = 20,  relative = true }))

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + ALT + W",   hl.dsp.workspace.toggle_special())
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
-- hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
-- hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Fullscreen
hl.bind(mainMod .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mainMod .. " + F",       hl.dsp.window.fullscreen({ mode = "maximized" }))

-- Cycle windows
hl.bind("ALT + Tab",         hl.dsp.window.cycle_next())
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ prev = true }))

-- Modes
hl.bind(mainMod .. " + D",        hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + CTRL + D", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + ALT + D",  hl.dsp.layout("togglesplit"))
