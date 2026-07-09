-- Switch window
hl.bind("CTRL + SPACE", hl.dsp.exec_cmd("hyprctl dispatch easymotion action:hyprctl dispatch focuswindow address:{}"))
-- Trigger overview
hl.bind(mainMod .. " + TAB", function() hl.plugin.hyprexpo.expo("toggle") end)

-- Scroll overview (niri-style workspace overview)
-- Plugin dispatchers are called as hl.plugin.<name>.<dispatcher>(...), per
-- the plugin's own README -- not hl.dsp.exec_cmd/exec_raw, which only spawn
-- external processes and never touch Hyprland's own dispatcher at all
-- (confirmed live: exec_raw("workspace", "3") returned "ok" but never
-- switched the workspace).
hl.bind("ALT + TAB", function()
    hl.plugin.scrolloverview.overview("toggle")
end)

-- --- Pyprland Keybindings ---

-- Scratchpad terminal (dropdown from top)
hl.bind(mainMod .. " + O",         hl.dsp.exec_cmd("pypr toggle term"))

-- System monitor (btm)
hl.bind(mainMod .. " + SHIFT + O", hl.dsp.exec_cmd("pypr toggle btm"))

-- Music player
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("pypr toggle music"))

-- Exposé - show all workspaces overview
hl.bind(mainMod .. " + I", function() hl.plugin.hyprexpo.expo("toggle") end)
