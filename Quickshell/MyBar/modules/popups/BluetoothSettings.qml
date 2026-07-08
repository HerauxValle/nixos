pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../config"
import "../../services"

Rectangle {
    id: root
    property string barScreenName: ""
    implicitWidth: BarConfig.sp(380)
    height: parent?.height ?? 480
    radius: BarConfig.sp(14)
    color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)
    border.color: Colors.popupBorder; border.width: 1
    clip: true

    MouseArea { anchors.fill: parent; onClicked: {} }

    property bool btPowered: Network.btOn
    property var connectedDevices: []
    property var pairedDevices: []
    property var discoveredDevices: []
    property bool scanning: false
    property int  scanDots: 0

    Component.onCompleted: root.refresh()
    onVisibleChanged: if (!visible) { scanOnProc.running = false; scanOffProc.running = true; scanDotTimer.stop(); root.scanning = false }

    component BtDeviceItem: Rectangle {
        id: btdi
        required property var    btDevice
        required property int    index
        property string mode: "paired"
        width: parent?.width ?? 300
        height: BarConfig.sp(44)
        radius: BarConfig.sp(10)
        color: mode === "connected"
               ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.12)
               : Colors.surfaceContainerHigh
        border.color: mode === "connected" ? Colors.primary : "transparent"
        border.width: mode === "connected" ? 1 : 0
        signal connectRequested(string mac)
        signal disconnectRequested(string mac)
        Item {
            anchors { left: parent.left; right: parent.right; leftMargin: BarConfig.sp(12); rightMargin: BarConfig.sp(12); top: parent.top; bottom: parent.bottom }
            Text {
                id: btdiIcon
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                font.pixelSize: BarConfig.fsLg; font.family: "Symbols Nerd Font Mono"
                color: btdi.mode === "connected" ? Colors.primary : Colors.colOnSurfaceVariant
                text: ""
            }
            Text {
                anchors { left: btdiIcon.right; leftMargin: BarConfig.sp(10); verticalCenter: parent.verticalCenter }
                text: (btdi.btDevice?.name || btdi.btDevice?.mac) ?? ""
                color: Colors.colOnSurface; font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                elide: Text.ElideRight; width: BarConfig.sp(160)
            }
            Rectangle {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: btdi.mode === "connected" ? 78 : 64; height: BarConfig.sp(26); radius: BarConfig.sp(13)
                color: btdi.mode === "connected"
                       ? Colors.surfaceContainerHigh
                       : Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.2)
                border.color: btdi.mode === "connected" ? Colors.outline : Colors.primary; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: btdi.mode === "connected" ? "Disconnect" : btdi.mode === "discovered" ? "Pair" : "Connect"
                    color: btdi.mode === "connected" ? Colors.colOnSurfaceVariant : Colors.primary
                    font.pixelSize: BarConfig.fsSm
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: btdi.mode === "connected" ? btdi.disconnectRequested(btdi.btDevice.mac) : btdi.connectRequested(btdi.btDevice.mac)
                }
            }
        }
    }

    // ── Header ────────────────────────────────────────────────────────────
    Item {
        id: hdr; width: parent.width; height: BarConfig.sp(46); z: 2
        Item {
            anchors { left: parent.left; right: parent.right; leftMargin: BarConfig.sp(16); rightMargin: BarConfig.sp(16); verticalCenter: parent.verticalCenter }
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: BarConfig.sp(8)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "←"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsLg
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.togglePopup("controlcenter", root.barScreenName) } }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Bluetooth"; color: Colors.colOnSurface; font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium }
            }
            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "✕"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fs
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.closePopup() } }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Colors.popupBorder; opacity: 0.8 }
    }

    // ── Body ──────────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors { top: hdr.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width; contentHeight: body.implicitHeight + 16; clip: true
        Column {
            id: body; width: flick.width - 28; x: 14; y: 10; spacing: BarConfig.sp(10)

            // Power toggle
            Item {
                width: parent.width; height: BarConfig.sp(40)
                Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Bluetooth Power"; color: Colors.colOnSurface; font.pixelSize: BarConfig.fs }
                Rectangle {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: BarConfig.sp(38); height: BarConfig.sp(22); radius: BarConfig.sp(11)
                    color: root.btPowered ? Colors.primary : Colors.surfaceContainerHigh
                    border.color: root.btPowered ? Colors.primary : Colors.outline; border.width: 1
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Rectangle {
                        width: BarConfig.sp(16); height: BarConfig.sp(16); radius: BarConfig.sp(8); anchors.verticalCenter: parent.verticalCenter
                        color: root.btPowered ? Colors.colOnPrimary : Colors.outline
                        x: root.btPowered ? parent.width - width - 3 : 3
                        Behavior on x     { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
                        Behavior on color { ColorAnimation  { duration: 180 } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: root.btPowered ? powerOffProc.running = true : powerOnProc.running = true }
                }
            }

            // Scan button
            Rectangle {
                width: parent.width; height: BarConfig.sp(34); radius: BarConfig.sp(10)
                color: root.scanning ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.08)
                                     : Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18)
                border.color: Colors.primary; border.width: 1
                Text { anchors.centerIn: parent; font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium; color: Colors.primary
                    text: root.scanning ? ("Scanning" + [".","..","..."][root.scanDots % 3]) : "Scan for Devices" }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: root.btPowered && !root.scanning
                    onClicked: { root.scanning = true; root.scanDots = 0; scanDotTimer.start(); scanOnProc.running = true; scanStopTimer.restart() } }
            }

            Rectangle { width: parent.width; height: 1; color: Colors.popupBorder; opacity: 0.8 }

            // Section label helper
            component SectionLabel: Text {
                required property string label
                text: label; color: Colors.primary; font.pixelSize: BarConfig.fsSm; font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.75
            }

            SectionLabel { label: "CONNECTED";    visible: root.connectedDevices.length  > 0 }
            Column { width: parent.width; spacing: BarConfig.sp(4); visible: root.connectedDevices.length > 0
                Repeater { model: root.connectedDevices
                    BtDeviceItem { required property var modelData; btDevice: modelData; mode: "connected"
                        onDisconnectRequested: (mac) => { disconnectProc.mac = mac; disconnectProc.running = true } } } }

            SectionLabel { label: "PAIRED DEVICES"; visible: root.pairedDevices.length   > 0 }
            Column { width: parent.width; spacing: BarConfig.sp(4); visible: root.pairedDevices.length > 0
                Repeater { model: root.pairedDevices
                    BtDeviceItem { required property var modelData; btDevice: modelData; mode: "paired"
                        onConnectRequested: (mac) => { btConnectProc.mac = mac; btConnectProc.running = true } } } }

            SectionLabel { label: "DISCOVERED";    visible: root.discoveredDevices.length > 0 }
            Column { width: parent.width; spacing: BarConfig.sp(4); visible: root.discoveredDevices.length > 0
                Repeater { model: root.discoveredDevices
                    BtDeviceItem { required property var modelData; btDevice: modelData; mode: "discovered"
                        onConnectRequested: (mac) => { btPairProc.mac = mac; btPairProc.running = true } } } }

            Item { height: BarConfig.sp(8) }
        }
    }

    // ── Timers ────────────────────────────────────────────────────────────
    Timer { id: scanDotTimer; interval: 500; repeat: true; onTriggered: root.scanDots++ }
    Timer { id: scanStopTimer; interval: 8000; repeat: false
        onTriggered: { scanOnProc.running = false; scanOffProc.running = true; scanDotTimer.stop(); root.scanning = false; root.refreshDevices() } }
    Timer { id: refreshTimer; interval: 5000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.refresh() }

    // ── Processes ─────────────────────────────────────────────────────────
    Process { id: scanOnProc;   command: ["bluetoothctl", "scan", "on"]  }
    Process { id: scanOffProc;  command: ["bluetoothctl", "scan", "off"] }
    Process { id: powerOnProc;  command: ["bluetoothctl", "power", "on"];  onExited: (c,s) => { if (c===0) { root.btPowered = true;  refreshTimer.restart() } } }
    Process { id: powerOffProc; command: ["bluetoothctl", "power", "off"]; onExited: (c,s) => { if (c===0) root.btPowered = false } }
    // Connect a paired device
    Process { id: btConnectProc;  property string mac: ""; command: ["bluetoothctl", "connect",    mac]; onExited: (c,s) => refreshTimer.restart() }
    Process { id: disconnectProc; property string mac: ""; command: ["bluetoothctl", "disconnect", mac]; onExited: (c,s) => refreshTimer.restart() }
    // Pair a new device: pair → trust → connect (all via bluetoothctl so PIN prompts work via agent)
    Process { id: btPairProc; property string mac: ""
        command: ["bash", "-c", "bluetoothctl pair " + mac + " && bluetoothctl trust " + mac + " && bluetoothctl connect " + mac]
        onExited: (c,s) => refreshTimer.restart()
    }

    Process { id: powerStateProc; command: ["bash", "-c", "bluetoothctl show | grep Powered"]
        stdout: StdioCollector { onStreamFinished: root.btPowered = text.indexOf("yes") >= 0 } }

    // Single combined query: get connected devices first, then all devices
    Process { id: connectedProc; command: ["bluetoothctl", "devices", "Connected"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.connectedDevices = text.trim().split("\n").filter(l => l.startsWith("Device"))
                    .map(l => { const p=l.split(" "); return { mac: p[1]||"", name: p.slice(2).join(" ").trim() } })
                    .filter(d => d.mac !== "")
                allDevicesProc.running = true
            }
        }
    }

    Process { id: allDevicesProc; command: ["bluetoothctl", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                const all = text.trim().split("\n").filter(l => l.startsWith("Device"))
                    .map(l => { const p=l.split(" "); return { mac: p[1]||"", name: p.slice(2).join(" ").trim() } })
                    .filter(d => d.mac !== "")
                const conn = root.connectedDevices.map(d => d.mac)
                root.pairedDevices = all.filter(d => !conn.includes(d.mac))
                // discovered = not in paired or connected (populated after scan)
                root.discoveredDevices = root.discoveredDevices.filter(d => !conn.includes(d.mac) && !root.pairedDevices.map(p=>p.mac).includes(d.mac))
            }
        }
    }

    Process { id: discoveredProc; command: ["bluetoothctl", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                const all = text.trim().split("\n").filter(l => l.startsWith("Device"))
                    .map(l => { const p=l.split(" "); return { mac: p[1]||"", name: p.slice(2).join(" ").trim() } })
                    .filter(d => d.mac !== "")
                const known = [...root.connectedDevices, ...root.pairedDevices].map(d => d.mac)
                root.discoveredDevices = all.filter(d => !known.includes(d.mac))
            }
        }
    }

    function refreshDevices() { connectedProc.running = true }
    function refreshDiscovered() { discoveredProc.running = true }
    function refresh() { powerStateProc.running = true; refreshDevices() }

    Rectangle {
        visible: flick.contentHeight > flick.height
        anchors.right: parent.right; anchors.rightMargin: BarConfig.sp(4)
        readonly property real _r: BarConfig.sp(14)
        readonly property real _thumbH: flick.visibleArea.heightRatio * flick.height
        y: Math.max(flick.y, Math.min(flick.y + flick.height - _thumbH - _r,
                    flick.y + flick.visibleArea.yPosition * flick.height))
        width: BarConfig.sp(3); height: _thumbH
        radius: BarConfig.sp(2); color: Colors.outline; opacity: 0.5; z: 5
    }
}
