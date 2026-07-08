pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"

// One OSD panel per screen — floats bottom-center when OSD is active.
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: osdWin
            required property ShellScreen modelData
            screen: modelData

            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:mybar-osd"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Float bottom-center: anchor only bottom
            anchors.bottom: true
            anchors.left:   false
            anchors.right:  false
            anchors.top:    false

            exclusiveZone: 0

            readonly property int osdW: Math.round(screen.width  * 0.1146)
            readonly property int osdH: Math.round(screen.height * 0.0472)

            implicitWidth:  osdW
            implicitHeight: osdH + 32   // bottom margin

            // Keep window alive while fading out
            visible: osdItem.opacity > 0.001

            Item {
                id: osdItem
                width:  osdWin.osdW
                height: osdWin.osdH

                opacity: OsdState.visible ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                // The OSD card
                Rectangle {
                    id: card
                    anchors.fill: parent
                    radius: 16
                    color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, 0.88)
                    border.color: Colors.popupBorder
                    border.width: 1

                    Row {
                        anchors {
                            left:   parent.left
                            right:  parent.right
                            top:    parent.top
                            leftMargin:  14
                            rightMargin: 14
                            topMargin:   12
                        }
                        spacing: 10

                        // Icon
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 20
                            font.family: "Symbols Nerd Font Mono"
                            color: Colors.primary
                            text: {
                                if (OsdState.mode === "volume") {
                                    if (OsdState.value <= 0)  return "\uF026"
                                    if (OsdState.value > 0.5) return "\uF028"
                                    return "\uF027"
                                }
                                if (OsdState.mode === "brightness") return "\uF0EB"
                                if (OsdState.mode === "wifi")       return "\uF1EB"
                                return "\uF028"
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            width: parent.width - 34

                            // Percentage / label
                            Text {
                                text: OsdState.label
                                color: Colors.colOnSurface
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }

                            // Progress bar
                            Rectangle {
                                width:  parent.width
                                height: 5
                                radius: 3
                                color:  Colors.surfaceContainerHigh

                                Rectangle {
                                    width:  Math.max(0, Math.min(1, OsdState.value)) * parent.width
                                    height: parent.height
                                    radius: parent.radius
                                    color:  Colors.primary
                                    Behavior on width {
                                        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
