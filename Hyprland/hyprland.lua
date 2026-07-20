-- --- HYPRLAND MAIN CONFIG ---

local function scriptDir()
  local str = debug.getinfo(1, "S").source:sub(2)
  return str:match("(.*/)")
end

HYPR_DIR = scriptDir():gsub("/$", "")

-- Scripts/ is a top-level Dotfiles folder (not Hyprland-specific), mapped
-- to ~/.config/scripts the same way HYPR_DIR's own directory is mapped to
-- ~/.config/hypr -- so it needs its own XDG-stable reference rather than
-- being reachable via HYPR_DIR .. "/Scripts/...".
SCRIPTS_DIR = os.getenv("HOME") .. "/.config/scripts"

-- 1.    Core Variables & Environment
require("Config.Core.env")                    -- 1.1  Environment Variables

-- 2.    Hardware / Input
require("Config.Core.monitors")               -- 2.1  Monitor Configuration
require("Config.Core.input")                  -- 2.2  Input

-- 3.    Visuals & UI
require("Config.UI.theme")                    -- 3.1  Look & Feel
require("Config.UI.workspaces")               -- 3.2  Workspaces

-- 4.    Window Management & Rules
require("Config.Rules.layout")                -- 4.1  Workspaces
require("Config.Rules.rules")                 -- 4.2  Permissions

-- 5.    Apps & Autostart
require("Config.Apps.defaults")               -- 5.1  Default Programms
require("Config.Apps.autostart")              -- 5.2  Autostart

-- 6.    Keybindings
require("Config.Binds.apps")                  -- 6.1  App launchers
require("Config.Binds.binds")                 -- 6.2  General KBM Shortcuts
require("Config.Binds.laptop")                -- 6.3  Laptop MEDIA shortcuts
-- require("Config.Binds.windows")            -- 6.4  Window management
require("Config.Binds.media")                 -- 6.5  Media control
require("Config.Binds.system")                -- 6.5  System controls
require("Config.Binds.plugins")               -- 6.6  Plugin binds
require("Config.Binds.canvas")                -- 6.7  Canvas plugin binds

-- 7.    Plugins
require("Config.Plugins.easymotion")          -- 7.1  Easy motion plugin
require("Config.Plugins.hyprexpo")            -- 7.2  Hyprexpo settings
require("Config.Plugins.borders-plus-plus")   -- 7.3  Enhanced borders
require("Config.Plugins.hyprwinwrap")         -- 7.4  Video wallpapers
require("Config.Plugins.dynamic-cursors")     -- 7.5  Cursor animations
require("Config.Plugins.hyprscroll")          -- 7.6  Hyprscroll config (built-in layout)
require("Config.Plugins.scrolloverview")      -- 7.7  Scroll overview (niri-style workspace overview)

-- 8.    Reactive
require("Config.Reactive.windowMode")         -- 8.1  Window mode manipulation
require("Floating.sourceMe")		          -- 8.2  Floating window manager configuration
