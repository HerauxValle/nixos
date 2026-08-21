-- Installed Apps
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("vesktop"))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("steam"))
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("keepassxc"))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("zapzap"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("code"))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("pinta"))

-- Deprecated yay installation
-- hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("modrinth-app"))

-- Variable based
hl.bind(mainMod .. " + Y", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(editor))
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))

-- Terminal apps | KITTY
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("kitty --hold -o confirm_os_window_close=0 nvim"))
hl.bind(mainMod .. " + ALT + E", hl.dsp.exec_cmd("kitty --hold -o confirm_os_window_close=0 yazi"))
hl.bind(mainMod .. " + ALT + T", hl.dsp.exec_cmd("kitty --hold -o confirm_os_window_close=0 fresh"))
hl.bind(mainMod .. " + ALT + V", hl.dsp.exec_cmd("kitty --hold -o confirm_os_window_close=0 pulsemixer"))

-- Usefull gadgets
-- hl.bind(mainMod .. " + ALT + SPACE", hl.dsp.exec_cmd("bash -c \"kitty --class menu-float -e fish -c launcher || " .. menu .. " -show drun\""))
hl.bind(mainMod .. " + P",           hl.dsp.exec_cmd("hyprpicker -a -f hex && notify-send \"Color copied!\""))
hl.bind(mainMod .. " + ALT + N",     hl.dsp.exec_cmd("nm-connection-editor"))
