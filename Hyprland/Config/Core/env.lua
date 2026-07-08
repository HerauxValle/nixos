-- --- Environment Variables for Hyprland ---

-- Cursor
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Force dark mode for Chromium/Vivaldi
hl.env("XCURSOR_THEME", "Adwaita")
-- hl.env("QT_STYLE_OVERRIDE", "Adwaita-Dark")

-- Wayland Support
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")

-- Theming in KDE applications
hl.env("QT_STYLE_OVERRIDE", "qt6ct-style")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- GTK dark theme
hl.env("GTK_THEME", "Adwaita:dark")
