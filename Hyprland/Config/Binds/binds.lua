-- --- Keybinds ---

-- Theming
hl.bind(mainMod .. " + K",               hl.dsp.exec_cmd("kvantummanager"))
hl.bind(mainMod .. " + SHIFT + K",       hl.dsp.exec_cmd("qt6ct"))
hl.bind(mainMod .. " + ALT + SHIFT + K", hl.dsp.exec_cmd("qt5ct"))

-- Screenshot
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(SCRIPTS_DIR .. "/screenshot.sh"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd(SCRIPTS_DIR .. "/screenshot.sh --clipboard --save"))

-- SWAYNC
hl.bind("SUPER + N",       hl.dsp.exec_cmd("swaync-client -t"))
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("swaync-client -d"))

hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + ALT + D",   hl.dsp.exec_cmd(SCRIPTS_DIR .. "/FWM.sh"))
