-- --- Default Programs ---

-- --------------------------
-- ----- Local Defaults -----
-- --------------------------

-- Adjust those for bindings; they do not affect system wide defaults!
-- Example: hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(editor)) in binds.lua

-- Simply do "hyprctl reload" and they are applied

-- Fallback logic, if you dont need that you can do 'terminal = "kitty"' without sh.



-- terminal    = "sh -c 'waveterm || konsole || kitty'"
-- fileManager = "sh -c 'dolphin || pcmanfm-qt'"
-- menu        = "sh -c 'wofi --show drun || rofi -show drun'"
-- browser     = "sh -c 'GTK_THEME=Adwaita:dark vivaldi --enable-features=WebUIDarkMode --force-dark-mode || firefox'"
-- editor      = "sh -c 'code-oss || nano'"

-- --------------------------
-- -- System-wide Defaults --
-- --------------------------

-- Adjust those for system wide defaults.
-- They do not affect binding variables like editor

-- IMPORTANT: "super+m" is NOT enough to apply those.
-- Log out and back in, or restart.

-- hl.env("EDITOR", "fresh")
-- hl.env("VISUAL", "code-oss")
-- hl.env("BROWSER", "vivaldi")

-- --------------------------
-- ----- More variables -----
-- --------------------------

-- Keyboard variables
mainMod = "SUPER"
