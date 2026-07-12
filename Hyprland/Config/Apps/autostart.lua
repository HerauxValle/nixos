-- Use hyprland.start event so processes launch AFTER the compositor is ready.
-- Lock file per session prevents re-running on config reload.
hl.on("hyprland.start", function()
    local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "unknown"
    local lock = "/tmp/hypr-autostart-" .. sig
    local f = io.open(lock, "r")
    if f then f:close(); return end
    io.open(lock, "w"):close()

    hl.exec_cmd(SCRIPTS_DIR .. "/Wallpaper/reload.sh")
    hl.exec_cmd(SCRIPTS_DIR .. "/defaultWS.sh")
    hl.exec_cmd(SCRIPTS_DIR .. "/defaultApps.sh")

    -- Nix-built plugins (Nixos/home/hyprland-plugins.nix), loaded the same
    -- way home-manager's own wayland.windowManager.hyprland.plugins does it
    -- under the hood (hyprctl plugin load) -- no hyprpm state store involved.
    -- Loads every .so nix put there, so adding a plugin to that file is the
    -- only change needed -- nothing to update here. exec_cmd spawns directly
    -- (no shell), so the loop needs an explicit bash -c like the other
    -- compound commands below.
    hl.exec_cmd("bash -c 'for f in " .. os.getenv("HOME") .. "/.local/share/hypr-plugins/*.so; do hyprctl plugin load \"$f\"; done'")

    -- Quickshell / MyBar. Via the XDG config path (home-manager symlinks
    -- Dotfiles/Quickshell -> ~/.config/quickshell), not the Dotfiles repo
    -- path, so this keeps working no matter where the repo itself lives.
    -- MyBar's own notifserver owns the notification D-Bus name, so swaync
    -- is intentionally not started here (they'd fight over it).
    hl.exec_cmd("bash ~/.config/quickshell/MyBar/main.sh --launch")
    hl.exec_cmd("pypr")
    hl.exec_cmd("mpd")

    hl.exec_cmd("/run/current-system/sw/libexec/polkit-gnome-authentication-agent-1")

    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP QT_QUICK_CONTROLS_STYLE")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP QT_QUICK_CONTROLS_STYLE")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
    hl.exec_cmd("bash -c 'prefix=$(ls /etc/xdg/menus/ 2>/dev/null | grep -m1 \"applications.menu$\" | sed \"s/applications.menu$//\"); XDG_MENU_PREFIX=${prefix:-} kbuildsycoca6 --noincremental'")
    hl.exec_cmd("xdg-settings set default-web-browser " .. browser .. ".desktop")
    hl.exec_cmd("xdg-mime default " .. editor .. ".desktop text/plain")
    hl.exec_cmd("xdg-mime default " .. fileManager .. ".desktop inode/directory")

    -- #TODO: Add hyprlandPlugins into nix!
    -- hl.exec_cmd("hyprpm reload")
end)
