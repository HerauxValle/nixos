-- sourceMe.lua -- require this from hyprland.lua only




local function scriptDir()
    local str = debug.getinfo(1, "S").source:sub(2)
    return str:match("(.*/)")
end

local hyprfloat  = scriptDir() .. "main.sh"
local hfMod      = "SUPER + CTRL + ALT"
local hfModShift = "SUPER + CTRL + ALT + SHIFT"

-- Reads DEFAULT_WIDTH_PCT/DEFAULT_HEIGHT_PCT straight from config/defaults.conf
-- instead of hardcoding them a second time here -- same numbers main.sh's own
-- --center action already uses, kept in one place.
local function readConfigValue(path, key)
    local f = io.open(path, "r")
    if not f then return nil end
    for line in f:lines() do
        local k, v = line:match("^(%u[%u_]*)%s*=%s*(.-)%s*$")
        if k == key then
            f:close()
            return (v:gsub('^"(.*)"$', "%1"))
        end
    end
    f:close()
    return nil
end

local defaultsConf = scriptDir() .. "config/defaults.conf"
local widthPct  = readConfigValue(defaultsConf, "DEFAULT_WIDTH_PCT") or "60"
local heightPct = readConfigValue(defaultsConf, "DEFAULT_HEIGHT_PCT") or "60"

-- Any window that opens floating gets sized to the same percentage of ITS
-- monitor (handles mixed-resolution multi-monitor setups correctly, unlike
-- a fixed pixel size) -- instead of whatever size it happened to request,
-- which for apps with no equivalent of kitty's own initial_window_width/
-- height can mean filling most of a tiling column.
--
-- window_rule's own "size" field doesn't accept percentage values here
-- (tested directly: "50% 50%" and "50%,50%" both silently no-op, falling
-- back to the window's own requested size) -- so this computes actual
-- pixels from the window's own monitor dimensions instead, via the
-- window.open event, reusing the exact resize+move dispatch calls
-- modules/move.sh already uses for --center.
hl.on("window.open", function(data)
    if not data.floating then return end
    local m = data.monitor
    local w = math.floor(m.width  * tonumber(widthPct)  / 100)
    local h = math.floor(m.height * tonumber(heightPct) / 100)
    local x = m.x + math.floor((m.width  - w) / 2)
    local y = m.y + math.floor((m.height - h) / 2)
    local addr = "address:" .. data.address
    hl.dispatch(hl.dsp.window.resize({ x = w, y = h, relative = false, window = addr }))
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = false, window = addr }))
end)

-- ── Autostart ────────────────────────────────────────────────────────────────
local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "unknown"
local lock = "/tmp/hypr-floatwm-" .. sig
local function lockExists()
    local f = io.open(lock, "r")
    if f then f:close(); return true end
    return false
end

-- This top-level script body runs synchronously during config parse, which
-- happens BEFORE hyprland.start fires (that event exists specifically to
-- run things after the compositor is ready) -- so on a genuine fresh start,
-- the lock file below doesn't exist yet.
local isFreshStart = not lockExists()

hl.on("hyprland.start", function()
    if lockExists() then return end
    io.open(lock, "w"):close()
    hl.exec_cmd(hyprfloat .. " --autostart")
end)

-- restore re-applies window rules on manual/config reloads within an
-- already-running session. Skipped on a genuine fresh start so a stale
-- STATE_FILE left in /tmp from a previous session can't override AUTOSTART
-- -- --autostart (above) is solely responsible for the fresh-start decision.
if not isFreshStart then
    hl.exec_cmd(hyprfloat .. " --restore")
end

-- ── Global float mode ────────────────────────────────────────────────────────
hl.bind(hfMod .. " + F", hl.dsp.exec_cmd(hyprfloat .. " --fullscreen"))
hl.bind(hfModShift .. " + T", hl.dsp.exec_cmd(hyprfloat .. " --toggle"))
hl.bind(hfModShift .. " + E", hl.dsp.exec_cmd(hyprfloat .. " --enable"))
hl.bind(hfModShift .. " + D", hl.dsp.exec_cmd(hyprfloat .. " --disable"))
hl.bind(hfMod .. " + G", hl.dsp.exec_cmd(hyprfloat .. " --grid"))

-- ── Directional snap ─────────────────────────────────────────────────────────
hl.bind(hfMod .. " + left",  hl.dsp.exec_cmd(hyprfloat .. " --dir:left"))
hl.bind(hfMod .. " + right", hl.dsp.exec_cmd(hyprfloat .. " --dir:right"))
hl.bind(hfMod .. " + up",    hl.dsp.exec_cmd(hyprfloat .. " --dir:up"))
hl.bind(hfMod .. " + down",  hl.dsp.exec_cmd(hyprfloat .. " --dir:down"))

-- ── Center ───────────────────────────────────────────────────────────────────
hl.bind(hfMod .. " + C", hl.dsp.exec_cmd(hyprfloat .. " --center"))
