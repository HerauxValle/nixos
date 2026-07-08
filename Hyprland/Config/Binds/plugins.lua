-- Switch window
hl.bind("CTRL + SPACE", hl.dsp.exec_cmd("hyprctl dispatch easymotion action:hyprctl dispatch focuswindow address:{}"))
-- Trigger overview
hl.bind(mainMod .. " + TAB", hl.dsp.exec_cmd("hyprctl dispatch hyprexpo:expo toggle"))

-- --- Pyprland Keybindings ---

-- Scratchpad terminal (dropdown from top)
hl.bind(mainMod .. " + O",         hl.dsp.exec_cmd("pypr toggle term"))

-- System monitor (btm)
hl.bind(mainMod .. " + SHIFT + O", hl.dsp.exec_cmd("pypr toggle btm"))

-- Music player
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("pypr toggle music"))

-- Exposé - show all workspaces overview
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("hyprctl dispatch hyprexpo:expo toggle"))
