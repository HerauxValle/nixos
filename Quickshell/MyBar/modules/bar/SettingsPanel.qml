pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

// Settings drop-down panel.  Clips to height=0 when closed (Bar.qml animates it).
// Changes to BarConfig take effect immediately but are not persisted across
// restarts — set AETHERA_* env vars in your theme file for persistence.
Rectangle {
    id: root
    radius: 12
    color: Colors.surfaceContainerHigh
    border.color: Colors.outlineVariant
    border.width: 1

    // ── Inline toggle button component ──────────────────────────────────
    component Btn: Rectangle {
        id: btn
        required property string label
        required property bool   active
        signal pick()

        implicitWidth:  lbl.implicitWidth + 18
        implicitHeight: 26
        radius: height / 2
        color: btn.active ? Colors.primary : Colors.secondaryContainer

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            id: lbl
            anchors.centerIn: parent
            text:  btn.label
            color: btn.active ? Colors.colOnPrimary : Colors.colOnSurfaceVariant
            font.pixelSize: 11
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.pick()
        }
    }

    // ── Content (clipped by parent) ───────────────────────────────────
    Column {
        anchors {
            fill:  parent
            topMargin:    10
            bottomMargin: 10
            leftMargin:   14
            rightMargin:  14
        }
        spacing: 8

        // Header + close
        Row {
            width: parent.width

            Text {
                text: "Bar Settings"
                color: Colors.colOnSurface
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Item { width: parent.width - closeBtn.implicitWidth - 100; height: 1 }

            Text {
                id: closeBtn
                // ✕ close
                text: "✕"
                color: Colors.colOnSurfaceVariant
                font.pixelSize: 13
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: BarConfig.settingsOpen = false
                }
            }
        }

        // Style row
        Row {
            spacing: 6
            width: parent.width

            Text {
                text: "Style"
                color: Colors.colOnSurfaceVariant
                font.pixelSize: 11
                width: 62
                anchors.verticalCenter: parent.verticalCenter
            }
            Btn {
                label: "Full Width"
                active: BarConfig.fillMode === "full"
                onPick: BarConfig.fillMode = "full"
            }
            Btn {
                label: "Pill"
                active: BarConfig.fillMode === "pill"
                onPick: BarConfig.fillMode = "pill"
            }
        }

        // Position row
        Row {
            spacing: 6
            width: parent.width

            Text {
                text: "Position"
                color: Colors.colOnSurfaceVariant
                font.pixelSize: 11
                width: 62
                anchors.verticalCenter: parent.verticalCenter
            }
            Btn {
                label: "Top"
                active: BarConfig.barPosition === "top"
                onPick: BarConfig.barPosition = "top"
            }
            Btn {
                label: "Bottom"
                active: BarConfig.barPosition === "bottom"
                onPick: BarConfig.barPosition = "bottom"
            }
        }

        // Alignment row — only relevant in pill mode
        Row {
            spacing: 6
            width: parent.width
            visible: BarConfig.fillMode === "pill"

            Text {
                text: "Align"
                color: Colors.colOnSurfaceVariant
                font.pixelSize: 11
                width: 62
                anchors.verticalCenter: parent.verticalCenter
            }
            Btn { label: "Left";   active: BarConfig.pillAlign === "left";   onPick: BarConfig.pillAlign = "left" }
            Btn { label: "Center"; active: BarConfig.pillAlign === "center"; onPick: BarConfig.pillAlign = "center" }
            Btn { label: "Right";  active: BarConfig.pillAlign === "right";  onPick: BarConfig.pillAlign = "right" }
        }

        // Theme hint
        Rectangle {
            width: parent.width
            height: 1
            color: Colors.outlineVariant
            opacity: 0.5
        }

        Text {
            width: parent.width
            text: "Theme: set AETHERA_* vars in launch.sh (or this shell's themes/*.env)"
            color: Colors.colOnSurfaceVariant
            font.pixelSize: 10
            wrapMode: Text.WordWrap
            opacity: 0.7
        }
    }
}
