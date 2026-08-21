pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Provides WiFi, Bluetooth, and LAN state via the netmonitor C++ binary.
// netmonitor uses libnm (reactive, no polling) for WiFi/LAN and a low-frequency
// poll thread for BlueZ BT. Emits JSON lines on every state change.
Singleton {
    id: root

    // ── WiFi ──────────────────────────────────────────────────────────────
    property string wifiSSID:    ""
    property int    wifiSignal:  0      // 0–100
    property string wifiIP:      ""
    property bool   wifiOn:      false
    property bool   wifiRadioOn: true

    // ── Bluetooth ─────────────────────────────────────────────────────────
    property bool   btOn:       false
    property string btDevice:   ""    // connected device name, "" if none

    // ── LAN / Ethernet ────────────────────────────────────────────────────
    property string lanInterface: ""
    property bool   lanConnected: false
    property string lanIP:        ""
    property string lanMAC:       ""
    property string lanSpeed:     ""

    // ── Airplane mode: both radios off ────────────────────────────────────
    readonly property bool airplaneMode: !wifiRadioOn && !btOn

    // ── JSON line handler (called from SplitParser so root must be in scope) ──
    function _handleLine(line: string) {
        if (!line || line[0] !== "{") return
        let obj
        try { obj = JSON.parse(line) } catch(e) { return }

        if (obj.type === "wifi") {
            root.wifiOn      = obj.on     ?? false
            root.wifiRadioOn = obj.radio  ?? true
            root.wifiSSID    = obj.ssid   ?? ""
            root.wifiSignal  = obj.signal ?? 0
            root.wifiIP      = obj.ip     ?? ""
        } else if (obj.type === "bt") {
            root.btOn     = obj.on     ?? false
            root.btDevice = obj.device ?? ""
        } else if (obj.type === "lan") {
            root.lanConnected = obj.connected ?? false
            root.lanInterface = obj.iface     ?? ""
            root.lanIP        = obj.ip        ?? ""
            root.lanMAC       = obj.mac       ?? ""
            root.lanSpeed     = obj.speed     ?? ""
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────
    function refresh() {
        _monitor.running = false
        _monitor.running = true
    }

    function toggleBluetooth() {
        _btToggle.command = ["bluetoothctl", "power", root.btOn ? "off" : "on"]
        _btToggle.running = true
    }

    function toggleWifi() {
        _wifiToggleProc.command = ["nmcli", "radio", "wifi", root.wifiRadioOn ? "off" : "on"]
        _wifiToggleProc.running = true
    }

    function toggleAirplaneMode() {
        if (root.airplaneMode) root._runAirplaneOff()
        else                   root._runAirplaneOn()
    }

    // ── netmonitor persistent process ─────────────────────────────────────
    Process {
        id: _monitor
        command: ["mybar-netmonitor"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root._handleLine(line)
        }
    }

    // ── WiFi radio toggle ─────────────────────────────────────────────────
    Process { id: _wifiToggleProc }

    // ── Bluetooth toggle ──────────────────────────────────────────────────
    Process { id: _btToggle }

    // ── Airplane mode on/off ──────────────────────────────────────────────
    function _buildAirplaneOnCmd() {
        const cmds = []
        if (BarConfig.apLockWifi)   cmds.push("nmcli radio wifi off 2>/dev/null")
        if (BarConfig.apLockBt)     cmds.push("bluetoothctl power off 2>/dev/null")
        if (BarConfig.apLockEth && root.lanInterface !== "")
            cmds.push("nmcli device disconnect " + root.lanInterface + " 2>/dev/null")
        if (BarConfig.apLockDaemons)
            cmds.push("systemctl --user stop syncthing.service nextcloud-desktop.service 2>/dev/null; true")
        if (BarConfig.apLockFirewall)
            cmds.push("nft add table inet mybar_block 2>/dev/null; nft add chain inet mybar_block output '{ type filter hook output priority 0; policy drop; }' 2>/dev/null")
        return cmds.length > 0 ? cmds.join("; ") + "; true" : "true"
    }

    function _buildAirplaneOffCmd() {
        const cmds = []
        if (BarConfig.apLockWifi)   cmds.push("nmcli radio wifi on 2>/dev/null")
        if (BarConfig.apLockBt)     cmds.push("bluetoothctl power on 2>/dev/null")
        if (BarConfig.apLockEth && root.lanInterface !== "")
            cmds.push("nmcli device connect " + root.lanInterface + " 2>/dev/null")
        if (BarConfig.apLockDaemons)
            cmds.push("systemctl --user start syncthing.service nextcloud-desktop.service 2>/dev/null; true")
        if (BarConfig.apLockFirewall)
            cmds.push("nft delete table inet mybar_block 2>/dev/null")
        return cmds.length > 0 ? cmds.join("; ") + "; true" : "true"
    }

    Process { id: _airplaneOnProc  }
    Process { id: _airplaneOffProc }

    function _runAirplaneOn()  { _airplaneOnProc.command  = ["bash", "-c", root._buildAirplaneOnCmd()];  _airplaneOnProc.running  = true }
    function _runAirplaneOff() { _airplaneOffProc.command = ["bash", "-c", root._buildAirplaneOffCmd()]; _airplaneOffProc.running = true }

    // ── Refresh when relevant popup opens ─────────────────────────────────
    Connections {
        target: BarConfig
        function onCurrentPopupChanged() {
            const p = BarConfig.currentPopup
            if (p === "controlcenter" || p === "wifi" || p === "bluetooth" || p === "airplanesettings")
                root.refresh()
        }
    }
}
