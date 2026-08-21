-- Reboot & Shutdown
hl.bind(mainMod .. " + ALT + R", hl.dsp.exec_cmd("systemctl reboot"))
hl.bind(mainMod .. " + ALT + S", hl.dsp.exec_cmd("systemctl poweroff"))
hl.bind(mainMod .. " + ALT + X", hl.dsp.exec_cmd("systemctl suspend"))

-- Hyprland
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd("kill -9 $(hyprctl activewindow -j | jq '.pid')"))
hl.bind(mainMod .. " + Q",         hl.dsp.window.close())
hl.bind(mainMod .. " + L",         hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl eval 'hl.dispatch(hl.dsp.exit())'"))

-- Refresh everything
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(SCRIPTS_DIR .. "/Reload/qsr.sh"))
