pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Settings persist to ~/.config/mybar/theme.env (sourced by launch.sh).
Singleton {
    // ── Layout ───────────────────────────────────────────────────────────
    property string fillMode:    { const m = Quickshell.env("AETHERA_MODE"); return (m === "full" || !m) ? "hanging" : m }
    property string barPosition: Quickshell.env("AETHERA_POS")    || "top"
    property string pillAlign:   Quickshell.env("AETHERA_ALIGN")  || "center"

    // Vertical mode: left/right positions rotate the bar to a side panel
    readonly property bool isVertical: barPosition === "left" || barPosition === "right"

    // Auto-hide: bar slides off-screen when mouse is not near it
    property bool autoHide:      false
    property int  autoHideDelay: 1500  // ms before hiding after mouse leaves

    // Backing init properties (read env once; user-settable props can be overwritten)
    property real _pillWidthPctInit: {
        const v = Quickshell.env("AETHERA_PILL_W"); return v ? parseFloat(v) : 1.0
    }
    property real pillWidthPct: _pillWidthPctInit

    // ── Appearance ───────────────────────────────────────────────────────
    // Bar font size (drives bar widgets only)
    property int _barFontSizeInit: {
        const v = Quickshell.env("AETHERA_FONT_SIZE"); return v ? parseInt(v) : 12
    }
    property int barFontSize: _barFontSizeInit

    // UI scale — independent multiplier for all popups/drawer/OSD (1.0 = default)
    property real _uiScaleInit: {
        const v = Quickshell.env("AETHERA_UI_SCALE"); return v ? parseFloat(v) : 1.0
    }
    property real uiScale: _uiScaleInit

    // Screen height — set by Bar.qml on startup; used to derive resolution-relative sizes.
    // Reference resolution is 1440p. sp(n) returns n scaled to current screen.
    property int screenH: 1440
    readonly property real _resSp: screenH / 1440.0
    // sp(n): convert a 1440p-reference pixel value to current screen size, then apply uiScale
    function sp(n) { return Math.round(n * _resSp * uiScale) }

    // Scaled font size helpers for popups (base 1440p sizes × res × uiScale)
    readonly property int fs:    sp(12)
    readonly property int fsSm:  sp(9)
    readonly property int fsXs:  sp(8)
    readonly property int fsLg:  sp(14)
    readonly property int fsMd:  sp(11)

    // Bar height (px) — separate backing so slider writes don't trigger rebinding
    property int _barHeightInit: {
        const v = Quickshell.env("AETHERA_HEIGHT")
        return v ? parseInt(v) : Math.max(32, barFontSize * 3)
    }
    property int barHeight: _barHeightInit

    // Gap between screen edge and bar (0 in full/hanging mode for flush edges)
    property int barMargin: {
        const v = Quickshell.env("AETHERA_MARGIN")
        if (v) return parseInt(v)
        if (fillMode === "hanging") return 0
        return 8   // auto: gap in pill
    }
    // Background opacity 0–1  (also settable from popup)
    property real _barOpacityInit: {
        const v = Quickshell.env("AETHERA_OPACITY"); return v ? parseFloat(v) : 0.72
    }
    property real barOpacity: _barOpacityInit

    // ── Widget visibility (toggle from settings popup) ───────────────────
    property bool showWorkspaces:   true
    property bool showMpris:        true
    property bool showClock:        true
    property bool showTray:         true
    property bool showVolume:       true
    property bool showNetwork:      true
    property bool showBrightness:   false   // no real backlight on this system
    property bool showCpu:          false
    property bool showMemory:       false
    property bool showActiveWindow: true

    // ── Widget ordering ───────────────────────────────────────────────────
    // Aether Ridge layout: numbered workspaces left, window title center,
    // media+volume+time right — matches reference image section 1
    property var leftWidgets:   ["workspaces"]
    property var centerWidgets: ["mpris", "activewindow"]
    property var rightWidgets:  ["tray", "network", "volume", "clock"]

    // ── Accent tint presets ───────────────────────────────────────────────
    property int tintIndex: { const v = Quickshell.env("AETHERA_TINT"); return v ? parseInt(v) : 0 }
    readonly property var tintPresets: ["#5C8FA5", "#A78BFA", "#34D399", "#F59E0B", "#F472B6", "#60A5FA"]

    // ── Popup state ───────────────────────────────────────────────────────
    property string currentPopup:       ""
    property string currentPopupScreen: ""   // screen name that owns the open popup
    property string lastPopupScreen:    ""   // persists after close — used by drawer gear icon
    property string primaryScreen:      ""   // fallback screen for IPC calls with no screen context
    property int    ctxWorkspaceId:     0    // set before opening workspacemenu popup
    property string capturingKey:       ""   // set by BarSettings during key capture

    function closePopup()                    { currentPopup = ""; currentPopupScreen = "" }
    function togglePopup(name, screenName)   {
        // empty screenName from IPC means "any screen" — match on name alone
        const sameScreen = !screenName || currentPopupScreen === screenName
        if (currentPopup === name && sameScreen) {
            currentPopup = ""; currentPopupScreen = ""
        } else {
            currentPopupScreen = screenName || lastPopupScreen || currentPopupScreen || primaryScreen
            lastPopupScreen = currentPopupScreen
            currentPopup = name
        }
    }
    function openBarSettings(screenName, tab) {
        const sameScreen = !screenName || currentPopupScreen === screenName
        if (currentPopup === "barsettings" && sameScreen) {
            currentPopup = ""; currentPopupScreen = ""; return
        }
        const s = screenName || lastPopupScreen || currentPopupScreen || primaryScreen
        currentPopupScreen = s; lastPopupScreen = s
        if (tab !== undefined) barSettingsTab = tab
        currentPopup = "barsettings"
    }

    // ── System theme: read Hyprland active border color as accent fallback ──
    Process {
        id: _hyprColorProc
        command: ["hyprctl", "getoption", "decoration:col.active_border", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (Quickshell.env("AETHERA_ACCENT") || Quickshell.env("AETHERA_PRIMARY")) return
                try {
                    const data = JSON.parse(text.trim())
                    const custom = data.custom || data.str || ""
                    const m = custom.match(/rgba\(([0-9a-fA-F]{6})/)
                    if (m) Colors._hyprAccent = Qt.color("#" + m[1])
                } catch(e) {}
            }
        }
    }

    // ── Persistence ───────────────────────────────────────────────────────
    property bool _ready: false
    Timer { id: _readyTimer; interval: 1200; onTriggered: { _saveTimer.stop(); _ready = true; applyAllBinds() } }
    Component.onCompleted: _readyTimer.start()

    function _buildContent() {
        return "AETHERA_MODE=" + fillMode + "\n" +
            "AETHERA_POS=" + barPosition + "\n" +
            "AETHERA_ALIGN=" + pillAlign + "\n" +
            "AETHERA_OPACITY=" + barOpacity + "\n" +
            "AETHERA_FONT_SIZE=" + barFontSize + "\n" +
            "AETHERA_UI_SCALE=" + uiScale + "\n" +
            "AETHERA_HEIGHT=" + barHeight + "\n" +
            "AETHERA_PILL_W=" + pillWidthPct + "\n" +
            "AETHERA_TINT=" + tintIndex + "\n" +
            "AETHERA_ACCENT=" + Colors.primary.toString().substring(0, 7) + "\n" +
            "AETHERA_TASKS='" + JSON.stringify(tasks) + "'\n" +
            "AETHERA_AP_WIFI=" + (apLockWifi ? "1" : "0") + "\n" +
            "AETHERA_AP_BT=" + (apLockBt ? "1" : "0") + "\n" +
            "AETHERA_AP_ETH=" + (apLockEth ? "1" : "0") + "\n" +
            "AETHERA_AP_DAEMONS=" + (apLockDaemons ? "1" : "0") + "\n" +
            "AETHERA_AP_FIREWALL=" + (apLockFirewall ? "1" : "0") + "\n" +
            "AETHERA_NOTIF_MAX=" + maxToastPopups + "\n" +
            "AETHERA_DRAWER_MAX=" + maxDrawerNotifs + "\n" +
            "AETHERA_BIND_DRAWER=" + bindDrawer + "\n" +
            "AETHERA_BIND_LAUNCHER=" + bindLauncher + "\n" +
            "AETHERA_BIND_CC=" + bindControlCenter + "\n" +
            "AETHERA_BIND_POWER=" + bindPower + "\n" +
            "AETHERA_BIND_SETTINGS=" + bindSettings + "\n" +
            "AETHERA_BIND_NOTIFICATIONS=" + bindNotifications + "\n" +
            "AETHERA_BIND_WIFI=" + bindWifi + "\n" +
            "AETHERA_BIND_BLUETOOTH=" + bindBluetooth + "\n" +
            "AETHERA_BIND_WORKSPACEMENU=" + bindWorkspaceMenu + "\n"
    }
    function _doSave() {
        if (!_ready) return
        if (_saveProc.running) { _saveTimer.restart(); return }
        const content = _buildContent()
        _saveProc.command = ["python3", "-c",
            "import os; p=os.path.expanduser('~/.config/mybar/theme.env'); os.makedirs(os.path.dirname(p),exist_ok=True); open(p,'w').write(" +
            JSON.stringify(content) + ")"]
        _saveProc.running = true
    }
    Process {
        id: _saveProc
        stderr: StdioCollector { onStreamFinished: if (text.length > 0) console.log("SAVE ERR: " + text) }
        onExited: function(exitCode) { if (exitCode !== 0) console.log("SAVE EXIT: " + exitCode) }
    }
    // Debounce: save 800ms after last change
    Timer { id: _saveTimer; interval: 800; onTriggered: _doSave() }
    function _schedSave() { _saveTimer.restart() }

    // ── Tasks persistence ─────────────────────────────────────────────────
    property var _tasksInit: {
        const v = Quickshell.env("AETHERA_TASKS")
        console.log("AETHERA_TASKS env: " + v)
        try { const p = v ? JSON.parse(v) : []; console.log("AETHERA_TASKS parsed: " + JSON.stringify(p)); return p } catch(e) { console.log("AETHERA_TASKS parse error: " + e); return [] }
    }
    property var tasks: _tasksInit

    function addTask(text) {
        tasks = [...tasks, text]
        _saveTimer.stop(); _doSave()
    }
    function removeTask(index) {
        const arr = [...tasks]; arr.splice(index, 1); tasks = arr
        _saveTimer.stop(); _doSave()
    }

    // ── Notification popups ───────────────────────────────────────────────
    property int _maxToastInit: { const v = Quickshell.env("AETHERA_NOTIF_MAX"); return v ? parseInt(v) : 3 }
    property int maxToastPopups: _maxToastInit
    onMaxToastPopupsChanged: _schedSave()

    property int _maxDrawerInit: { const v = Quickshell.env("AETHERA_DRAWER_MAX"); return v ? parseInt(v) : 20 }
    property int maxDrawerNotifs: _maxDrawerInit
    onMaxDrawerNotifsChanged: _schedSave()

    // Which tab is open in BarSettings (0=Appearance,1=Bar,2=Widgets,3=Notifications)
    property int barSettingsTab: 0

    // ── Airplane mode lockdown settings ───────────────────────────────────
    property bool _apWifiInit:     { const v = Quickshell.env("AETHERA_AP_WIFI");     return v ? v === "1" : true  }
    property bool _apBtInit:       { const v = Quickshell.env("AETHERA_AP_BT");       return v ? v === "1" : true  }
    property bool _apEthInit:      { const v = Quickshell.env("AETHERA_AP_ETH");      return v ? v === "1" : true  }
    property bool _apDaemonsInit:  { const v = Quickshell.env("AETHERA_AP_DAEMONS");  return v ? v === "1" : false }
    property bool _apFirewallInit: { const v = Quickshell.env("AETHERA_AP_FIREWALL"); return v ? v === "1" : false }

    property bool apLockWifi:     _apWifiInit
    property bool apLockBt:       _apBtInit
    property bool apLockEth:      _apEthInit
    property bool apLockDaemons:  _apDaemonsInit
    property bool apLockFirewall: _apFirewallInit

    onApLockWifiChanged:     _schedSave()
    onApLockBtChanged:       _schedSave()
    onApLockEthChanged:      _schedSave()
    onApLockDaemonsChanged:  _schedSave()
    onApLockFirewallChanged: _schedSave()

    // ── Keybinds ──────────────────────────────────────────────────────────
    // Each bind stored as "MOD+MOD+KEY" string, e.g. "SUPER+Space"
    // Empty string means unbound. Defaults match the old hyprland.conf binds.
    readonly property var _bindDefaults: ({
        "drawer":        Quickshell.env("AETHERA_DEFAULT_DRAWER")        || "SUPER+B",
        "launcher":      Quickshell.env("AETHERA_DEFAULT_LAUNCHER")      || "SUPER+Space",
        "controlcenter": Quickshell.env("AETHERA_DEFAULT_CC")            || "SUPER+C",
        "power":         Quickshell.env("AETHERA_DEFAULT_POWER")         || "SUPER+Escape",
        "settings":      Quickshell.env("AETHERA_DEFAULT_SETTINGS")      || "SUPER+comma",
        "notifications": Quickshell.env("AETHERA_DEFAULT_NOTIFICATIONS") || "SUPER+SHIFT+N",
        "wifi":          Quickshell.env("AETHERA_DEFAULT_WIFI")          || "SUPER+SHIFT+W",
        "bluetooth":     Quickshell.env("AETHERA_DEFAULT_BLUETOOTH")     || "SUPER+SHIFT+B",
        "workspacemenu": Quickshell.env("AETHERA_DEFAULT_WORKSPACEMENU") || "SUPER+Tab"
    })

    function _parseBind(env) {
        const v = Quickshell.env(env)
        return (v !== undefined && v !== null && v !== "") ? v : ""
    }

    property string bindDrawer:         _parseBind("AETHERA_BIND_DRAWER")         || _bindDefaults["drawer"]
    property string bindLauncher:       _parseBind("AETHERA_BIND_LAUNCHER")       || _bindDefaults["launcher"]
    property string bindControlCenter:  _parseBind("AETHERA_BIND_CC")             || _bindDefaults["controlcenter"]
    property string bindPower:          _parseBind("AETHERA_BIND_POWER")          || _bindDefaults["power"]
    property string bindSettings:       _parseBind("AETHERA_BIND_SETTINGS")       || _bindDefaults["settings"]
    property string bindNotifications:  _parseBind("AETHERA_BIND_NOTIFICATIONS")  || _bindDefaults["notifications"]
    property string bindWifi:           _parseBind("AETHERA_BIND_WIFI")           || _bindDefaults["wifi"]
    property string bindBluetooth:      _parseBind("AETHERA_BIND_BLUETOOTH")      || _bindDefaults["bluetooth"]
    property string bindWorkspaceMenu:  _parseBind("AETHERA_BIND_WORKSPACEMENU")  || _bindDefaults["workspacemenu"]

    // Tracks the last-applied bind string per action so we can unbind the OLD one
    property var _activeBinds: ({})

    onBindDrawerChanged:         { _schedSave(); if (_ready) _updateBind("drawer",        bindDrawer) }
    onBindLauncherChanged:       { _schedSave(); if (_ready) _updateBind("launcher",      bindLauncher) }
    onBindControlCenterChanged:  { _schedSave(); if (_ready) _updateBind("controlcenter", bindControlCenter) }
    onBindPowerChanged:          { _schedSave(); if (_ready) _updateBind("power",         bindPower) }
    onBindSettingsChanged:       { _schedSave(); if (_ready) _updateBind("settings",      bindSettings) }
    onBindNotificationsChanged:  { _schedSave(); if (_ready) _updateBind("notifications", bindNotifications) }
    onBindWifiChanged:           { _schedSave(); if (_ready) _updateBind("wifi",          bindWifi) }
    onBindBluetoothChanged:      { _schedSave(); if (_ready) _updateBind("bluetooth",     bindBluetooth) }
    onBindWorkspaceMenuChanged:  { _schedSave(); if (_ready) _updateBind("workspacemenu", bindWorkspaceMenu) }

    readonly property string _qsPath: Quickshell.shellPath("")

    function _bindSpec(action, bindStr) {
        const parts = bindStr.split("+")
        const key   = parts[parts.length - 1].trim()
        const mods  = parts.slice(0, parts.length - 1).map(m => m.trim()).join(" + ")
        const combo = mods ? mods + " + " + key : key
        const cmd   = "qs ipc -p " + _qsPath + " call " + action + " onMessage \\\"\\\""
        return "hl.bind(\"" + combo + "\", hl.dsp.exec_cmd(\"" + cmd + "\"))"
    }

    function _unbindSpec(bindStr) {
        const parts = bindStr.split("+")
        const key   = parts[parts.length - 1].trim()
        const mods  = parts.slice(0, parts.length - 1).map(m => m.trim()).join(" + ")
        const combo = mods ? mods + " + " + key : key
        return "hl.unbind(\"" + combo + "\")"
    }

    function _updateBind(action, newBindStr) {
        const old = _activeBinds[action]
        let lua = ""
        if (old && old !== newBindStr) lua += _unbindSpec(old) + "; "
        if (newBindStr) lua += _bindSpec(action, newBindStr) + "; "
        if (lua) {
            _runHyprctl(["hyprctl", "eval", lua])
            const updated = Object.assign({}, _activeBinds)
            updated[action] = newBindStr
            _activeBinds = updated
        } else {
            const updated = Object.assign({}, _activeBinds)
            delete updated[action]
            _activeBinds = updated
        }
    }

    function applyAllBinds() {
        const actions = [
            ["drawer",        bindDrawer],
            ["launcher",      bindLauncher],
            ["controlcenter", bindControlCenter],
            ["power",         bindPower],
            ["settings",      bindSettings],
            ["notifications", bindNotifications],
            ["wifi",          bindWifi],
            ["bluetooth",     bindBluetooth],
            ["workspacemenu", bindWorkspaceMenu]
        ]
        let lua = ""
        for (const [action, bindStr] of actions) {
            if (!bindStr) continue
            lua += _unbindSpec(bindStr) + "; "
            lua += _bindSpec(action, bindStr) + "; "
        }
        if (lua) _runHyprctl(["hyprctl", "eval", lua])
        _activeBinds = {
            "drawer":        bindDrawer,
            "launcher":      bindLauncher,
            "controlcenter": bindControlCenter,
            "power":         bindPower,
            "settings":      bindSettings,
            "notifications": bindNotifications,
            "wifi":          bindWifi,
            "bluetooth":     bindBluetooth,
            "workspacemenu": bindWorkspaceMenu
        }
    }

    property var _bindQueue: []
    function _runHyprctl(cmd) {
        if (!_hyprctlBindProc.running) {
            _hyprctlBindProc.command = cmd
            _hyprctlBindProc.running = true
        } else {
            _bindQueue.push(cmd)
        }
    }
    Process {
        id: _hyprctlBindProc
        onExited: {
            if (BarConfig._bindQueue.length > 0) {
                _hyprctlBindProc.command = BarConfig._bindQueue.shift()
                _hyprctlBindProc.running = true
            }
        }
    }

    onFillModeChanged:    _schedSave()
    onBarPositionChanged: _schedSave()
    onPillAlignChanged:   _schedSave()
    onBarOpacityChanged:  _schedSave()
    onBarFontSizeChanged: _schedSave()
    onUiScaleChanged:     _schedSave()
    onBarHeightChanged:   _schedSave()
    onPillWidthPctChanged: _schedSave()
    onTintIndexChanged: {
        Colors.primary = Qt.color(tintPresets[tintIndex])
        _schedSave()
    }

    function setCpu(v) {
        showCpu = v
        const w = rightWidgets.slice()
        if (v) {
            if (!w.includes("cpu")) {
                const ci = w.indexOf("clock")
                w.splice(ci >= 0 ? ci : w.length, 0, "cpu")
            }
        } else {
            const i = w.indexOf("cpu"); if (i >= 0) w.splice(i, 1)
        }
        rightWidgets = w
    }

    function setMemory(v) {
        showMemory = v
        const w = rightWidgets.slice()
        if (v) {
            if (!w.includes("memory")) {
                const ci = w.indexOf("clock")
                w.splice(ci >= 0 ? ci : w.length, 0, "memory")
            }
        } else {
            const i = w.indexOf("memory"); if (i >= 0) w.splice(i, 1)
        }
        rightWidgets = w
    }
}
