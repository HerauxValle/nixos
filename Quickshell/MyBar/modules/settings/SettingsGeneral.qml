pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../../config"
import "../../services"

Item {
    id: root
    clip: true

    // Launch-at-login process helpers
    Process {
        id: sysdEnable
        command: ["systemctl", "--user", "enable", "--now", "mybar.service"]
    }
    Process {
        id: sysdDisable
        command: ["systemctl", "--user", "disable", "--now", "mybar.service"]
    }
    Process {
        id: sysdCheck
        command: ["systemctl", "--user", "is-enabled", "mybar.service"]
        stdout: StdioCollector {
            onStreamFinished: loginToggle.checked = text.trim() === "enabled"
        }
    }

    Component.onCompleted: sysdCheck.running = true

    // ── Shared component: section label ─────────────────────────────────
    component SLabel: Text {
        color: Colors.primary; font.pixelSize: 9
        font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.8
    }

    component HR: Rectangle {
        width: parent?.width ?? 400; height: 1
        color: Colors.outlineVariant; opacity: 0.5
    }

    component SRow: Item {
        id: sr
        required property string label
        default property alias children: srRight.data
        width: parent?.width ?? 400; implicitHeight: 36

        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: sr.label; color: Colors.colOnSurface; font.pixelSize: 12
        }
        Item {
            id: srRight
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            implicitWidth: childrenRect.width; implicitHeight: childrenRect.height
        }
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
                Behavior on x     { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
                Behavior on color { ColorAnimation  { duration: 160 } }
            }
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: { tog.checked = !tog.checked; tog.toggled(tog.checked) }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width; contentHeight: col.implicitHeight + 32; clip: true

        Column {
            id: col
            width: parent.width - 48
            x: 24; y: 20
            spacing: 10

            SLabel { text: "ABOUT" }

            Item {
                width: parent.width; height: 60
                Rectangle {
                    anchors.fill: parent; radius: 12
                    color: Colors.surfaceContainerHigh
                    Column {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 16 }
                        spacing: 4
                        Text { text: "MyBar"; color: Colors.colOnSurface; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { text: "Quickshell 0.3.0  |  Aether Ridge"; color: Colors.colOnSurfaceVariant; font.pixelSize: 11 }
                    }
                }
            }

            HR {}
            SLabel { text: "STARTUP" }
            SRow {
                label: "Launch at Login"
                Toggle {
                    id: loginToggle
                    onToggled: (v) => v ? sysdEnable.running = true : sysdDisable.running = true
                }
            }

            HR {}
            SLabel { text: "KEYBINDS" }

            Repeater {
                model: [
                    { key: "SUPER + B",     action: "Toggle Drawer" },
                    { key: "SUPER + Space", action: "Toggle Launcher" },
                    { key: "SUPER + D",     action: "Toggle Dashboard" }
                ]
                Item {
                    required property var modelData
                    required property int index
                    width: parent?.width ?? 400; height: 32
                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: modelData.action; color: Colors.colOnSurface; font.pixelSize: 12
                    }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        radius: 6; height: 24
                        width: kbLabel.implicitWidth + 16
                        color: Colors.surfaceContainerHigh
                        border.color: Colors.outline; border.width: 1
                        Text {
                            id: kbLabel
                            anchors.centerIn: parent
                            text: modelData.key; color: Colors.colOnSurfaceVariant
                            font.pixelSize: 10; font.family: "monospace"
                        }
                    }
                }
            }

            HR {}
            SLabel { text: "DANGER ZONE" }

            Item {
                width: parent.width; height: 36
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 120; height: 30; radius: 8
                    color: Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.15)
                    border.color: Colors.error; border.width: 1
                    Text {
                        anchors.centerIn: parent; text: "Reset Defaults"
                        color: Colors.error; font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            BarConfig.tintIndex      = 0
                            BarConfig.fillMode       = "hanging"
                            BarConfig.barPosition    = "top"
                            BarConfig.autoHide       = false
                            BarConfig.pillWidthPct   = 0.65
                            BarConfig.barOpacity     = 0.72
                            BarConfig.barFontSize    = 12
                        }
                    }
                }
            }
            Item { height: 8 }
        }
    }
}
