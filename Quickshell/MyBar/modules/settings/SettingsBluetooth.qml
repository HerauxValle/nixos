pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../../config"
import "../../services"

Item {
    id: root
    clip: true

    property bool btPowered: false
    property var connectedDevices: []
    property var pairedDevices: []
    property bool scanning: false
    property int  scanDots: 0

    Component.onCompleted: root.refresh()

    function refresh() { powerStateProc.running = true; connectedProc.running = true; allDevicesProc.running = true }
    function refreshDevices() { connectedProc.running = true; allDevicesProc.running = true }

    Process { id: scanOnProc;   command: ["bluetoothctl", "scan", "on"]  }
    Process { id: scanOffProc;  command: ["bluetoothctl", "scan", "off"] }
    Process { id: powerOnProc;  command: ["bluetoothctl", "power", "on"];
              onExited: (c, s) => { if (c === 0) { root.btPowered = true; root.refreshDevices() } } }
    Process { id: powerOffProc; command: ["bluetoothctl", "power", "off"];
              onExited: (c, s) => { if (c === 0) root.btPowered = false } }
    Process { id: btConnectProc; property string mac: ""; command: ["bluetoothctl", "connect", mac];
              onExited: (c, s) => root.refreshDevices() }
    Process { id: disconnectProc; property string mac: ""; command: ["bluetoothctl", "disconnect", mac];
              onExited: (c, s) => root.refreshDevices() }
    Process { id: powerStateProc; command: ["bash", "-c", "bluetoothctl show | grep Powered"]
        stdout: StdioCollector { onStreamFinished: root.btPowered = text.indexOf("yes") >= 0 } }
    Process { id: connectedProc; command: ["bluetoothctl", "devices", "Connected"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.connectedDevices = text.trim().split("\n").filter(l => l.startsWith("Device"))
                    .map(l => { const p = l.split(" "); return { mac: p[1] || "", name: p.slice(2).join(" ") } })
            }
        }
    }
    Process { id: allDevicesProc; command: ["bluetoothctl", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                const conn = root.connectedDevices.map(d => d.mac)
                root.pairedDevices = text.trim().split("\n").filter(l => l.startsWith("Device"))
                    .map(l => { const p = l.split(" "); return { mac: p[1] || "", name: p.slice(2).join(" ") } })
                    .filter(d => !conn.includes(d.mac))
            }
        }
    }

    Timer { id: scanDotTimer; interval: 500; repeat: true; onTriggered: root.scanDots++ }
    Timer { id: scanStopTimer; interval: 8000
        onTriggered: { scanOnProc.running = false; scanOffProc.running = true; scanDotTimer.stop(); root.scanning = false; root.refreshDevices() } }

    component SLabel: Text {
        color: Colors.primary; font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.8
    }
    component HR: Rectangle { width: parent?.width ?? 400; height: 1; color: Colors.outlineVariant; opacity: 0.5 }

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 32; clip: true
        Column {
            id: col; width: parent.width - 48; x: 24; y: 20; spacing: 10

            SLabel { text: "BLUETOOTH" }

            Item {
                width: parent.width; height: 36
                Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                       text: "Bluetooth Power"; color: Colors.colOnSurface; font.pixelSize: 12 }
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 38; height: 22; radius: 11
                    color: root.btPowered ? Colors.primary : Colors.surfaceContainerHigh
                    border.color: root.btPowered ? Colors.primary : Colors.outline; border.width: 1
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Rectangle {
                        width: 16; height: 16; radius: 8; anchors.verticalCenter: parent.verticalCenter
                        color: root.btPowered ? Colors.colOnPrimary : Colors.outline
                        x: root.btPowered ? parent.width - width - 3 : 3
                        Behavior on x     { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
                        Behavior on color { ColorAnimation  { duration: 180 } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: root.btPowered ? powerOffProc.running = true : powerOnProc.running = true }
                }
            }

            Rectangle {
                width: parent.width; height: 36; radius: 10
                color: root.scanning ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.08)
                                     : Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18)
                border.color: Colors.primary; border.width: 1
                Text { anchors.centerIn: parent; font.pixelSize: 11; font.weight: Font.Medium; color: Colors.primary
                       text: root.scanning ? ("Scanning" + [".","..","..."][root.scanDots % 3]) : "Scan for Devices" }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    enabled: root.btPowered && !root.scanning
                    onClicked: { root.scanning = true; root.scanDots = 0; scanDotTimer.start(); scanOnProc.running = true; scanStopTimer.restart() } }
            }

            HR {}
            SLabel { text: "CONNECTED DEVICES"; visible: root.connectedDevices.length > 0 }

            Column {
                width: parent.width; spacing: 4; visible: root.connectedDevices.length > 0
                Repeater {
                    model: root.connectedDevices
                    Item {
                        required property var modelData; required property int index
                        width: parent?.width ?? 400; height: 40
                        Rectangle {
                            anchors.fill: parent; radius: 10; color: Colors.surfaceContainerHigh
                            Row {
                                anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 0
                                Column {
                                    spacing: 2; width: parent.width - 80
                                    Text { text: modelData.name || "Unknown"; color: Colors.colOnSurface; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width }
                                    Text { text: modelData.mac; color: Colors.colOnSurfaceVariant; font.pixelSize: 9 }
                                }
                                Rectangle {
                                    width: 72; height: 26; radius: 13
                                    color: Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.15)
                                    border.color: Colors.error; border.width: 1
                                    Text { anchors.centerIn: parent; text: "Disconnect"; color: Colors.error; font.pixelSize: 10 }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { disconnectProc.mac = modelData.mac; disconnectProc.running = true } }
                                }
                            }
                        }
                    }
                }
            }

            HR { visible: root.pairedDevices.length > 0 }
            SLabel { text: "PAIRED DEVICES"; visible: root.pairedDevices.length > 0 }

            Column {
                width: parent.width; spacing: 4; visible: root.pairedDevices.length > 0
                Repeater {
                    model: root.pairedDevices
                    Item {
                        required property var modelData; required property int index
                        width: parent?.width ?? 400; height: 40
                        Rectangle {
                            anchors.fill: parent; radius: 10; color: Colors.surfaceContainerHigh
                            Row {
                                anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 0
                                Column {
                                    spacing: 2; width: parent.width - 72
                                    Text { text: modelData.name || "Unknown"; color: Colors.colOnSurface; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width }
                                    Text { text: modelData.mac; color: Colors.colOnSurfaceVariant; font.pixelSize: 9 }
                                }
                                Rectangle {
                                    width: 64; height: 26; radius: 13; color: Colors.primary
                                    Text { anchors.centerIn: parent; text: "Connect"; color: Colors.colOnPrimary; font.pixelSize: 10 }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { btConnectProc.mac = modelData.mac; btConnectProc.running = true } }
                                }
                            }
                        }
                    }
                }
            }
            Item { height: 8 }
        }
    }
}
