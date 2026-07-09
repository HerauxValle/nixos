-- Switch window
hl.bind("CTRL + SPACE", hl.dsp.exec_cmd("hyprctl dispatch easymotion action:hyprctl dispatch focuswindow address:{}"))
-- Trigger overview
hl.bind(mainMod .. " + TAB", hl.dsp.exec_raw("hyprexpo:expo toggle"))

-- Scroll overview (niri-style workspace overview)
-- exec_raw, not exec_cmd("hyprctl dispatch ...") -- this fork's hyprctl CLI
-- re-interprets `dispatch`'s argument as Lua now, so the classic
-- "DISPATCHER ARGS" string (incl. this plugin's own README example) throws
-- a Lua parse error instead of dispatching. exec_raw dispatches directly,
-- skipping that broken CLI round-trip.
hl.bind("ALT + TAB", hl.dsp.exec_raw("scrolloverview:overview toggle"))

-- --- Pyprland Keybindings ---

-- Scratchpad terminal (dropdown from top)
hl.bind(mainMod .. " + O",         hl.dsp.exec_cmd("pypr toggle term"))

-- System monitor (btm)
hl.bind(mainMod .. " + SHIFT + O", hl.dsp.exec_cmd("pypr toggle btm"))

-- Music player
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("pypr toggle music"))

-- Exposé - show all workspaces overview
hl.bind(mainMod .. " + I", hl.dsp.exec_raw("hyprexpo:expo toggle"))
