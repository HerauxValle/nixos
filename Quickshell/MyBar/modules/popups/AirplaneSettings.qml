pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../config"
import "../../services"

Rectangle {
    id: root
    property string barScreenName: ""
    implicitWidth: BarConfig.sp(380)
    height: parent?.height ?? 360
    radius: BarConfig.sp(14)
    color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)
    border.color: Colors.popupBorder
    border.width: 1

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
        id: contentCol
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────
        Item {
            id: hdr
            width: parent.width; height: BarConfig.sp(48)
            Row {
                anchors { left: parent.left; leftMargin: BarConfig.sp(6); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(4)
                Rectangle {
                    width: BarConfig.sp(28); height: BarConfig.sp(28); radius: BarConfig.sp(8)
                    color: Colors.surfaceContainerHigh
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        anchors.centerIn: parent
                        text: "‹"; font.pixelSize: BarConfig.fsLg; color: Colors.colOnSurfaceVariant
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: BarConfig.togglePopup("controlcenter", root.barScreenName)
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Airplane Lockdown"
                    font.pixelSize: BarConfig.fsSm; font.weight: Font.Medium
                    color: Colors.colOnSurface
                }
            }
            // Master airplane toggle
            Row {
                anchors { right: parent.right; rightMargin: BarConfig.sp(12); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(6)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Network.airplaneMode ? "ON" : "OFF"
                    font.pixelSize: BarConfig.fsXs; font.weight: Font.Medium
                    color: Network.airplaneMode ? Colors.primary : Colors.colOnSurfaceVariant
                }
                Rectangle {
                    id: masterToggle
                    width: BarConfig.sp(36); height: BarConfig.sp(20); radius: BarConfig.sp(10)
                    color: Network.airplaneMode
                           ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.85)
                           : Colors.surfaceContainerHigh
                    border.color: Network.airplaneMode ? Colors.primary : Colors.outline; border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: BarConfig.sp(14); height: BarConfig.sp(14); radius: BarConfig.sp(7)
                        anchors.verticalCenter: parent.verticalCenter
                        x: Network.airplaneMode ? parent.width - width - BarConfig.sp(3) : BarConfig.sp(3)
                        color: Network.airplaneMode ? Colors.surface : Colors.outline
                        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: Network.toggleAirplaneMode()
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Colors.popupBorder; opacity: 0.6 }

        // ── Description ───────────────────────────────────────────────────
        Text {
            width: parent.width - BarConfig.sp(24)
            x: BarConfig.sp(12)
            topPadding: BarConfig.sp(10); bottomPadding: BarConfig.sp(6)
            text: "Choose what gets disabled when airplane mode is turned on."
            font.pixelSize: BarConfig.fsXs; color: Colors.colOnSurfaceVariant; opacity: 0.75
            wrapMode: Text.WordWrap
        }

        // ── Lockdown options ──────────────────────────────────────────────
        Column {
            width: parent.width - BarConfig.sp(16)
            x: BarConfig.sp(8)
            spacing: BarConfig.sp(4)
            bottomPadding: BarConfig.sp(12)

            Repeater {
                model: [
                    { key: "wifi",     label: "Wi-Fi",           sub: "Disable wireless radio",          icon: "", get: function() { return BarConfig.apLockWifi    }, set: function(v) { BarConfig.apLockWifi    = v } },
                    { key: "bt",       label: "Bluetooth",       sub: "Power off bluetooth adapter",     icon: "", get: function() { return BarConfig.apLockBt      }, set: function(v) { BarConfig.apLockBt      = v } },
                    { key: "eth",      label: "Ethernet",        sub: "Disconnect wired interface",      icon: "", get: function() { return BarConfig.apLockEth     }, set: function(v) { BarConfig.apLockEth     = v } },
                    { key: "daemons",  label: "Sync Daemons",    sub: "Stop Syncthing, Nextcloud, etc.", icon: "", get: function() { return BarConfig.apLockDaemons }, set: function(v) { BarConfig.apLockDaemons = v } },
                    { key: "firewall", label: "Block All Traffic","sub": "nftables output drop rule",    icon: "", get: function() { return BarConfig.apLockFirewall}, set: function(v) { BarConfig.apLockFirewall= v } }
                ]

                delegate: Rectangle {
                    id: optRow
                    required property var modelData
                    required property int index
                    width: parent.width; height: BarConfig.sp(52); radius: BarConfig.sp(10)
                    color: Colors.surfaceContainerHigh
                    border.color: Colors.popupBorder; border.width: 1

                    // icon
                    Text {
                        id: optIcon
                        anchors { left: parent.left; leftMargin: BarConfig.sp(12); verticalCenter: parent.verticalCenter }
                        text: optRow.modelData.icon
                        font.pixelSize: BarConfig.fsLg; font.family: "Symbols Nerd Font Mono"
                        color: Colors.colOnSurfaceVariant
                    }

                    Column {
                        anchors { left: optIcon.right; leftMargin: BarConfig.sp(10); verticalCenter: parent.verticalCenter }
                        spacing: BarConfig.sp(2)
                        Text {
                            text: optRow.modelData.label
                            font.pixelSize: BarConfig.fsSm; font.weight: Font.Medium; color: Colors.colOnSurface
                        }
                        Text {
                            text: optRow.modelData.sub
                            font.pixelSize: BarConfig.fsXs; color: Colors.colOnSurfaceVariant; opacity: 0.7
                        }
                    }

                    // Toggle — index-based to keep live BarConfig bindings
                    Rectangle {
                        id: optToggle
                        readonly property bool checked: {
                            switch(optRow.index) {
                                case 0: return BarConfig.apLockWifi
                                case 1: return BarConfig.apLockBt
                                case 2: return BarConfig.apLockEth
                                case 3: return BarConfig.apLockDaemons
                                case 4: return BarConfig.apLockFirewall
                                default: return false
                            }
                        }
                        function toggle() {
                            switch(optRow.index) {
                                case 0: BarConfig.apLockWifi     = !BarConfig.apLockWifi;     break
                                case 1: BarConfig.apLockBt       = !BarConfig.apLockBt;       break
                                case 2: BarConfig.apLockEth      = !BarConfig.apLockEth;      break
                                case 3: BarConfig.apLockDaemons  = !BarConfig.apLockDaemons;  break
                                case 4: BarConfig.apLockFirewall = !BarConfig.apLockFirewall; break
                            }
                        }
                        width: BarConfig.sp(36); height: BarConfig.sp(20); radius: BarConfig.sp(10)
                        anchors { right: parent.right; rightMargin: BarConfig.sp(12); verticalCenter: parent.verticalCenter }
                        color: checked
                               ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.85)
                               : Colors.surfaceContainer
                        border.color: checked ? Colors.primary : Colors.outline; border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Rectangle {
                            width: BarConfig.sp(14); height: BarConfig.sp(14); radius: BarConfig.sp(7)
                            anchors.verticalCenter: parent.verticalCenter
                            x: optToggle.checked ? parent.width - width - BarConfig.sp(3) : BarConfig.sp(3)
                            color: optToggle.checked ? Colors.surface : Colors.outline
                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: optToggle.toggle()
                        }
                    }
                }
            }
        }

        // ── Warning note for firewall ─────────────────────────────────────
        Text {
            width: parent.width - BarConfig.sp(24)
            x: BarConfig.sp(12)
            bottomPadding: BarConfig.sp(10)
            text: "Note: Firewall rule requires root/sudo privileges (nft)."
            font.pixelSize: BarConfig.fsXs; color: Colors.colOnSurfaceVariant; opacity: 0.5
            wrapMode: Text.WordWrap
        }
    }
}
