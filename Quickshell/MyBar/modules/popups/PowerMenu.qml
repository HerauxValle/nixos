pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../config"

Rectangle {
    id: root
    implicitWidth: BarConfig.sp(380)
    height: parent?.height ?? 340
    radius: BarConfig.sp(14)
    color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)
    border.color: Colors.popupBorder
    border.width: 1

    MouseArea { anchors.fill: parent; onClicked: {} }

    // ── Header ────────────────────────────────────────────────────────────────
    Item {
        id: hdr
        width: parent.width; height: BarConfig.sp(46); z: 2

        Item {
            anchors { left: parent.left; right: parent.right; leftMargin: BarConfig.sp(16); rightMargin: BarConfig.sp(16) }
            anchors.verticalCenter: parent.verticalCenter

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: BarConfig.sp(8)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2190"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsLg
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: BarConfig.closePopup()
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Power"; color: Colors.colOnSurface
                    font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                }
            }

            Text {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: "\u2715"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fs
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.closePopup() }
            }
        }

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Colors.popupBorder; opacity: 0.8 }
    }

    // ── Power actions (scrollable) ─────────────────────────────────────────────
    Flickable {
        id: pmFlick
        anchors { top: hdr.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentWidth: width
        contentHeight: pmCol.implicitHeight + 20
        clip: true

        Column {
            id: pmCol
            anchors { left: parent.left; right: parent.right; leftMargin: BarConfig.sp(14); rightMargin: BarConfig.sp(14) }
            y: 10
            spacing: BarConfig.sp(6)


        // ── Lock ─────────────────────────────────────────────────────────────
        Process { id: lockProc; command: ["loginctl", "lock-session"] }
        Rectangle {
            width: parent.width; height: BarConfig.sp(48); radius: BarConfig.sp(10)
            color: Colors.surfaceContainerHigh
            border.color: Colors.popupBorder; border.width: 1
            Row {
                anchors { left: parent.left; leftMargin: BarConfig.sp(16); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(12)
                Text {
                    font.pixelSize: BarConfig.fsLg; font.family: "Symbols Nerd Font Mono"
                    color: Colors.colOnSurfaceVariant; text: "\uF023"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Lock"; color: Colors.colOnSurface; font.pixelSize: BarConfig.fsMd
                }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { lockProc.running = true; BarConfig.closePopup() }
            }
        }

        // ── Suspend ──────────────────────────────────────────────────────────
        Process { id: suspendProc; command: ["systemctl", "suspend"] }
        Rectangle {
            width: parent.width; height: BarConfig.sp(48); radius: BarConfig.sp(10)
            color: Colors.surfaceContainerHigh
            border.color: Colors.popupBorder; border.width: 1

            Row {
                anchors { left: parent.left; leftMargin: BarConfig.sp(16); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(12)
                Text {
                    font.pixelSize: Math.round(16 * BarConfig.uiScale)
                    color: Colors.colOnSurfaceVariant
                    text: "\uF186"
                    font.family: "Symbols Nerd Font Mono"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Suspend"
                    font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                    color: Colors.colOnSurface
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { suspendProc.running = true; BarConfig.closePopup() }
            }
        }

        // ── Hibernate ────────────────────────────────────────────────────────
        Process { id: hibernateProc; command: ["systemctl", "hibernate"] }
        Rectangle {
            width: parent.width; height: BarConfig.sp(48); radius: BarConfig.sp(10)
            color: Colors.surfaceContainerHigh
            border.color: Colors.popupBorder; border.width: 1

            Row {
                anchors { left: parent.left; leftMargin: BarConfig.sp(16); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(12)
                Text {
                    font.pixelSize: Math.round(16 * BarConfig.uiScale)
                    color: Colors.colOnSurfaceVariant
                    text: "\uF2DC"
                    font.family: "Symbols Nerd Font Mono"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Hibernate"
                    font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                    color: Colors.colOnSurface
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { hibernateProc.running = true; BarConfig.closePopup() }
            }
        }

        // ── Reboot ───────────────────────────────────────────────────────────
        Rectangle {
            id: rebootTile
            property bool confirm: false
            width: parent.width; height: BarConfig.sp(48); radius: BarConfig.sp(10)
            color: confirm
                   ? Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.20)
                   : Colors.surfaceContainerHigh
            border.color: confirm ? Colors.error : Colors.popupBorder; border.width: 1
            Behavior on color { ColorAnimation { duration: 100 } }

            Process { id: rebootProc; command: ["systemctl", "reboot"] }
            Timer {
                id: rebootTimer; interval: 3000
                onTriggered: rebootTile.confirm = false
            }

            Row {
                anchors { left: parent.left; leftMargin: BarConfig.sp(16); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(12)
                Text {
                    font.pixelSize: Math.round(16 * BarConfig.uiScale)
                    color: rebootTile.confirm ? Colors.error : Colors.colOnSurfaceVariant
                    text: "\uF2F1"
                    font.family: "Symbols Nerd Font Mono"
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                Text {
                    text: rebootTile.confirm ? "Confirm \u2014 click again" : "Reboot"
                    font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                    color: rebootTile.confirm ? Colors.error : Colors.colOnSurface
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (rebootTile.confirm) {
                        rebootProc.running = true
                    } else {
                        rebootTile.confirm = true
                        rebootTimer.restart()
                    }
                }
            }
        }

        // ── Shut Down ────────────────────────────────────────────────────────
        Rectangle {
            id: shutdownTile
            property bool confirm: false
            width: parent.width; height: BarConfig.sp(48); radius: BarConfig.sp(10)
            color: confirm
                   ? Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.20)
                   : Colors.surfaceContainerHigh
            border.color: confirm ? Colors.error : Colors.popupBorder; border.width: 1
            Behavior on color { ColorAnimation { duration: 100 } }

            Process { id: shutdownProc; command: ["systemctl", "poweroff"] }
            Timer {
                id: shutdownTimer; interval: 3000
                onTriggered: shutdownTile.confirm = false
            }

            Row {
                anchors { left: parent.left; leftMargin: BarConfig.sp(16); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(12)
                Text {
                    font.pixelSize: Math.round(16 * BarConfig.uiScale)
                    color: shutdownTile.confirm ? Colors.error : Colors.colOnSurfaceVariant
                    text: "\uF011"
                    font.family: "Symbols Nerd Font Mono"
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                Text {
                    text: shutdownTile.confirm ? "Confirm \u2014 click again" : "Shut Down"
                    font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                    color: shutdownTile.confirm ? Colors.error : Colors.colOnSurface
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (shutdownTile.confirm) {
                        shutdownProc.running = true
                    } else {
                        shutdownTile.confirm = true
                        shutdownTimer.restart()
                    }
                }
            }
        }

        // ── Log Out ──────────────────────────────────────────────────────────
        Process { id: logoutProc; command: ["hyprctl", "dispatch", "exit"] }
        Rectangle {
            width: parent.width; height: BarConfig.sp(48); radius: BarConfig.sp(10)
            color: Colors.surfaceContainerHigh
            border.color: Colors.popupBorder; border.width: 1

            Row {
                anchors { left: parent.left; leftMargin: BarConfig.sp(16); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(12)
                Text {
                    font.pixelSize: Math.round(16 * BarConfig.uiScale)
                    color: Colors.colOnSurfaceVariant
                    text: "\uF2F5"
                    font.family: "Symbols Nerd Font Mono"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Log Out"
                    font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                    color: Colors.colOnSurface
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { logoutProc.running = true }
            }
        }
    }

}
}
