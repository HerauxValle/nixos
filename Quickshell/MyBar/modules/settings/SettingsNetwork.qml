pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: root
    clip: true

    component SLabel: Text {
        color: Colors.primary; font.pixelSize: 9
        font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.8
    }
    component HR: Rectangle {
        width: parent?.width ?? 400; height: 1; color: Colors.outlineVariant; opacity: 0.5
    }
    component InfoRow: Item {
        id: ir; required property string label; required property string value
        width: parent?.width ?? 400; height: 32
        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: ir.label; color: Colors.colOnSurfaceVariant; font.pixelSize: 12 }
        Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
               text: ir.value; color: Colors.colOnSurface; font.pixelSize: 12; elide: Text.ElideRight
               width: 200; horizontalAlignment: Text.AlignRight }
    }
    component Toggle: Item {
        id: tog; property bool checked: false; signal toggled(bool v)
        implicitWidth: 38; implicitHeight: 22
        Rectangle {
            anchors.fill: parent; radius: height / 2
            color: tog.checked ? Colors.primary : Colors.surfaceContainerHigh
            border.color: tog.checked ? Colors.primary : Colors.outline; border.width: 1
            Behavior on color { ColorAnimation { duration: 160 } }
            Rectangle {
                width: 16; height: 16; radius: 8; color: tog.checked ? Colors.colOnPrimary : Colors.outline
                anchors.verticalCenter: parent.verticalCenter
                x: tog.checked ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
                Behavior on color { ColorAnimation { duration: 160 } }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: { tog.checked = !tog.checked; tog.toggled(tog.checked) } }
    }

    Component.onCompleted: Network.refresh()

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 32; clip: true
        Column {
            id: col; width: parent.width - 48; x: 24; y: 20; spacing: 10

            SLabel { text: "WI-FI" }

            Item {
                width: parent.width; height: 36
                Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                       text: "Wi-Fi"; color: Colors.colOnSurface; font.pixelSize: 12 }
                Item {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    implicitWidth: wifiTog.implicitWidth; implicitHeight: wifiTog.implicitHeight
                    Toggle {
                        id: wifiTog
                        checked: Network.wifiRadioOn
                        onToggled: Network.toggleWifi()
                    }
                }
            }

            InfoRow { label: "SSID";       value: Network.wifiSSID || "Not connected" }
            InfoRow { label: "IP Address"; value: Network.wifiIP   || "—" }
            InfoRow {
                label: "Signal"
                value: {
                    if (!Network.wifiOn) return "—"
                    const s = Network.wifiSignal ?? 0
                    if (s > 75) return "Excellent (" + s + "%)"
                    if (s > 50) return "Good (" + s + "%)"
                    if (s > 25) return "Fair (" + s + "%)"
                    return "Weak (" + s + "%)"
                }
            }

            HR {}
            SLabel { text: "ETHERNET" }
            InfoRow { label: "Interface"; value: Network.lanInterface || "—" }
            InfoRow { label: "Status";    value: Network.lanConnected ? "Connected" : "Disconnected" }
            InfoRow { label: "IP";        value: Network.lanIP   || "—" }
            InfoRow { label: "MAC";       value: Network.lanMAC  || "—" }
            InfoRow { label: "Speed";     value: Network.lanSpeed || "—" }

            HR {}
            SLabel { text: "BLUETOOTH" }
            Item {
                width: parent.width; height: 36
                Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                       text: "Bluetooth"; color: Colors.colOnSurface; font.pixelSize: 12 }
                Item {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    implicitWidth: btTog.implicitWidth; implicitHeight: btTog.implicitHeight
                    Toggle {
                        id: btTog
                        checked: Network.btOn
                        onToggled: Network.toggleBluetooth()
                    }
                }
            }
            InfoRow { label: "Device"; value: Network.btDevice || (Network.btOn ? "No device" : "Off") }

            Item { height: 8 }
        }
    }
}
