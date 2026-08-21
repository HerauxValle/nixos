pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

// Comprehensive bar settings popup.
// Changes are live (no restart needed except those marked with ↺).
// Persist with AETHERA_* env vars in your theme file (see launch.sh).
Rectangle {
    id: root
    implicitWidth: 340
    implicitHeight: content.implicitHeight + 24
    radius: 14
    color: Colors.popupBg
    border.color: Colors.popupBorder
    border.width: 1
    clip: true

    // ── Reusable components ───────────────────────────────────────────

    // Row with label on left, control on right
    component SRow: Item {
        id: srow
        required property string label
        default property alias children: rightSlot.data
        implicitWidth: parent?.width ?? 300
        implicitHeight: Math.max(24, rightSlot.implicitHeight + 4)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: srow.label
            color: Colors.colOnSurface
            font.pixelSize: BarConfig.fs
        }
        Item {
            id: rightSlot
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }

    // Toggle button (pill style)
    component Btn: Rectangle {
        id: btn
        required property string label
        required property bool   active
        signal pick()

        implicitWidth:  lbl.implicitWidth + 16
        implicitHeight: 26
        radius: height / 2
        color: btn.active ? Colors.primary : Colors.secondaryContainer
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            id: lbl
            anchors.centerIn: parent
            text: btn.label
            color: btn.active ? Colors.colOnPrimary : Colors.colOnSurfaceVariant
            font.pixelSize: BarConfig.fsMd
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: btn.pick()
        }
    }

    // Toggle switch (on/off)
    component Toggle: Item {
        id: tog
        property bool checked: false
        signal toggled(bool v)

        implicitWidth: 38; implicitHeight: 22

        Rectangle {
            anchors.fill: parent; radius: height / 2
            color: tog.checked ? Colors.primary : Colors.surfaceContainerHigh
            border.color: tog.checked ? Colors.primary : Colors.outline
            border.width: 1
            Behavior on color { ColorAnimation { duration: 160 } }

            Rectangle {
                width: 16; height: 16; radius: 8
                color: tog.checked ? Colors.colOnPrimary : Colors.outline
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

    // Horizontal rule
    component HR: Rectangle {
        implicitWidth: parent?.width ?? 300
        implicitHeight: 1
        color: Colors.outlineVariant
        opacity: 0.5
    }

    // Section label
    component SLabel: Text {
        color: Colors.primary
        font.pixelSize: BarConfig.fsSm
        font.weight: Font.Medium
        font.letterSpacing: 1
        opacity: 0.85
    }

    // ── Main content ──────────────────────────────────────────────────
    Column {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.margins: 16
        spacing: 10

        // Header
        Row {
            width: parent.width
            Text {
                text: "Bar Settings"
                color: Colors.colOnSurface
                font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { width: parent.width - closeX.implicitWidth - 96; height: 1 }
            Text {
                id: closeX
                text: "✕"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: BarConfig.closePopup()
                }
            }
        }

        HR {}

        // ── LAYOUT ───────────────────────────────────────────────────
        SLabel { text: "LAYOUT" }

        SRow {
            label: "Style"
            Row {
                spacing: 4
                Btn { label: "Full Width"; active: BarConfig.fillMode === "full";   onPick: BarConfig.fillMode = "full" }
                Btn { label: "Pill";       active: BarConfig.fillMode === "pill";   onPick: BarConfig.fillMode = "pill" }
            }
        }

        SRow {
            label: "Position"
            Row {
                spacing: 4
                Btn { label: "Top";    active: BarConfig.barPosition === "top";    onPick: BarConfig.barPosition = "top" }
                Btn { label: "Bottom"; active: BarConfig.barPosition === "bottom"; onPick: BarConfig.barPosition = "bottom" }
            }
        }

        SRow {
            visible: BarConfig.fillMode === "pill"
            label: "Align"
            Row {
                spacing: 4
                Btn { label: "Left";   active: BarConfig.pillAlign === "left";   onPick: BarConfig.pillAlign = "left" }
                Btn { label: "Center"; active: BarConfig.pillAlign === "center"; onPick: BarConfig.pillAlign = "center" }
                Btn { label: "Right";  active: BarConfig.pillAlign === "right";  onPick: BarConfig.pillAlign = "right" }
            }
        }

        // Opacity slider
        SRow {
            label: "Opacity"
            Row {
                spacing: 8
                Item {
                    implicitWidth: 130; implicitHeight: 20
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        id: opTrack
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 4; radius: 2
                        color: Colors.surfaceContainerHigh
                        Rectangle {
                            width: (BarConfig.barOpacity - 0.4) / 0.6 * opTrack.width
                            height: parent.height; radius: parent.radius
                            color: Colors.primary
                        }
                        Rectangle {
                            width: 14; height: 14; radius: 7
                            color: Colors.primary
                            anchors.verticalCenter: parent.verticalCenter
                            x: (BarConfig.barOpacity - 0.4) / 0.6 * (opTrack.width - width)
                        }
                        MouseArea {
                            anchors { fill: parent; margins: -8 }
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: (m) => {
                                if (!pressed) return
                                BarConfig.barOpacity = Math.max(0.4, Math.min(1,
                                    0.4 + (m.x / opTrack.width) * 0.6))
                            }
                            onClicked: (m) => {
                                BarConfig.barOpacity = Math.max(0.4, Math.min(1,
                                    0.4 + (m.x / opTrack.width) * 0.6))
                            }
                        }
                    }
                }
                Text {
                    text: Math.round(BarConfig.barOpacity * 100) + "%"
                    color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        HR {}

        // ── WIDGETS ──────────────────────────────────────────────────
        SLabel { text: "WIDGETS" }

        SRow {
            label: "Workspaces"
            Toggle { checked: BarConfig.showWorkspaces; onToggled: (v) => BarConfig.showWorkspaces = v }
        }
        SRow {
            label: "MPRIS Player"
            Toggle { checked: BarConfig.showMpris; onToggled: (v) => BarConfig.showMpris = v }
        }
        SRow {
            label: "Clock"
            Toggle { checked: BarConfig.showClock; onToggled: (v) => BarConfig.showClock = v }
        }
        SRow {
            label: "System Tray"
            Toggle { checked: BarConfig.showTray; onToggled: (v) => BarConfig.showTray = v }
        }
        SRow {
            label: "Volume"
            Toggle { checked: BarConfig.showVolume; onToggled: (v) => BarConfig.showVolume = v }
        }
        SRow {
            label: "Network"
            Toggle { checked: BarConfig.showNetwork; onToggled: (v) => BarConfig.showNetwork = v }
        }

        HR {}

        // ── THEME HINT ───────────────────────────────────────────────
        SLabel { text: "THEME" }

        Text {
            width: parent.width
            text: "Colours: set AETHERA_* in themes/*.env\nReload: qsr (or Super+R)"
            color: Colors.colOnSurfaceVariant
            font.pixelSize: BarConfig.fsSm; opacity: 0.65; wrapMode: Text.WordWrap
        }

        Item { height: 4 }  // bottom padding
    }
}
