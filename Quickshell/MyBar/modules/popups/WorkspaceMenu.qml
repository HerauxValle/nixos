pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../config"

Rectangle {
    id: root
    implicitWidth: BarConfig.sp(380)
    height: parent?.height ?? 160
    radius: BarConfig.sp(14)
    color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)
    border.color: Colors.popupBorder
    border.width: 1

    MouseArea { anchors.fill: parent; onClicked: {} }

    readonly property int wsId: BarConfig.ctxWorkspaceId

    Column {
        anchors { fill: parent; margins: BarConfig.sp(14) }
        spacing: 0

        // Header
        Item {
            width: parent.width; height: BarConfig.sp(32)
            Text {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                text: "Workspace " + root.wsId
                color: Colors.colOnSurface; font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
            }
            Text {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: "✕"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fs
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.closePopup() }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Colors.popupBorder; opacity: 0.6 }

        Item { height: BarConfig.sp(8) }

        // Action: Switch to
        Rectangle {
            width: parent.width; height: BarConfig.sp(40); radius: BarConfig.sp(10)
            color: swHov.containsMouse
                   ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.12)
                   : "transparent"
            HoverHandler { id: swHov }
            Row {
                anchors { left: parent.left; leftMargin: BarConfig.sp(8); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(10)
                Text { text: ""; font.family: "Symbols Nerd Font Mono"; font.pixelSize: BarConfig.fsMd; color: Colors.primary; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Switch to workspace " + root.wsId; font.pixelSize: BarConfig.fs; color: Colors.colOnSurface; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { Hyprland.dispatch("workspace " + root.wsId); BarConfig.closePopup() }
            }
        }

        // Action: Move focused window here
        Rectangle {
            width: parent.width; height: BarConfig.sp(40); radius: BarConfig.sp(10)
            color: mvHov.containsMouse
                   ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.12)
                   : "transparent"
            HoverHandler { id: mvHov }
            Row {
                anchors { left: parent.left; leftMargin: BarConfig.sp(8); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(10)
                Text { text: ""; font.family: "Symbols Nerd Font Mono"; font.pixelSize: BarConfig.fsMd; color: Colors.primary; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Move window to workspace " + root.wsId; font.pixelSize: BarConfig.fs; color: Colors.colOnSurface; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { Hyprland.dispatch("movetoworkspace " + root.wsId); BarConfig.closePopup() }
            }
        }

        // Action: Move and follow
        Rectangle {
            width: parent.width; height: BarConfig.sp(40); radius: BarConfig.sp(10)
            color: mfHov.containsMouse
                   ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.12)
                   : "transparent"
            HoverHandler { id: mfHov }
            Row {
                anchors { left: parent.left; leftMargin: BarConfig.sp(8); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(10)
                Text { text: ""; font.family: "Symbols Nerd Font Mono"; font.pixelSize: BarConfig.fsMd; color: Colors.primary; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Move here and follow"; font.pixelSize: BarConfig.fs; color: Colors.colOnSurface; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { Hyprland.dispatch("movetoworkspacesilent " + root.wsId); Hyprland.dispatch("workspace " + root.wsId); BarConfig.closePopup() }
            }
        }
    }
}
