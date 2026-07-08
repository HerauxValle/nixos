pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../config"
import "../widgets"
import "../../services"

Rectangle {
    id: barContent
    required property string barScreenName

    // pill = all rounded; full = all square; hanging/float top bar = top square bottom round;
    // hanging/float bottom bar = top round bottom square; vertical = all round
    readonly property real _r: height / 2
    readonly property bool _bottom: BarConfig.barPosition === "bottom"
    readonly property bool _pill:   BarConfig.fillMode === "pill"
    // hanging: square edges at screen side, round on open side; pill: all round; vertical: all round
    topLeftRadius:     BarConfig.isVertical ? _r : (_pill ? _r : (_bottom ? _r : 0))
    topRightRadius:    BarConfig.isVertical ? _r : (_pill ? _r : (_bottom ? _r : 0))
    bottomLeftRadius:  BarConfig.isVertical ? _r : (_pill ? _r : (_bottom ? 0 : _r))
    bottomRightRadius: BarConfig.isVertical ? _r : (_pill ? _r : (_bottom ? 0 : _r))

    color: Qt.rgba(Colors.surface.r,
                   Colors.surface.g,
                   Colors.surface.b,
                   BarConfig.barOpacity)

    border.width: 1
    border.color: Colors.popupBorder

    // Glass highlight: only show on floating pill modes (not when flush to screen edge)
    Rectangle {
        visible: BarConfig.fillMode === "pill"
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 1
        color: Qt.rgba(1, 1, 1, 0.10)
        topLeftRadius:  barContent.topLeftRadius
        topRightRadius: barContent.topRightRadius
    }

    Behavior on topLeftRadius     { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
    Behavior on topRightRadius    { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
    Behavior on bottomLeftRadius  { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
    Behavior on bottomRightRadius { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }

    // ── Vertical layout (left/right bar) ────────────────────────────────
    Item {
        visible: BarConfig.isVertical
        anchors.fill: parent

        // Top section: drawer + workspaces
        Column {
            id: vTop
            anchors { top: parent.top; topMargin: 10; horizontalCenter: parent.horizontalCenter }
            spacing: 8

            // Drawer toggle
            Item {
                implicitWidth: BarConfig.sp(22); implicitHeight: BarConfig.sp(22)
                anchors.horizontalCenter: parent.horizontalCenter
                Text {
                    anchors.centerIn: parent; text: ""
                    font.family: "Symbols Nerd Font Mono"; font.pixelSize: BarConfig.sp(13)
                    color: ShellState.drawerOpen ? Colors.primary : Colors.colOnSurfaceVariant
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleDrawer() }
            }

            // Workspace dots — one per active/occupied workspace
            Column {
                id: vWsCol
                visible: BarConfig.showWorkspaces
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4

                readonly property int activeWsId: Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1
                readonly property int wsCount: {
                    const vals = Hyprland.workspaces.values
                    if (vals.length === 0) return 1
                    return Math.max(...vals.map(w => w.id), vWsCol.activeWsId)
                }

                Repeater {
                    model: vWsCol.wsCount
                    Item {
                        id: vWsItem
                        required property int index
                        readonly property int  wsId:   index + 1
                        readonly property bool active: vWsItem.wsId === vWsCol.activeWsId
                        implicitWidth: BarConfig.sp(22); implicitHeight: BarConfig.sp(22)

                        Rectangle {
                            anchors.centerIn: parent
                            width: vWsItem.active ? 18 : 6; height: vWsItem.active ? 18 : 6
                            radius: vWsItem.active ? 5 : 3
                            color: vWsItem.active
                                   ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.25)
                                   : Colors.colOnSurfaceVariant
                            border.color: vWsItem.active ? Colors.primary : "transparent"
                            border.width: vWsItem.active ? 1 : 0
                            opacity: vWsItem.active ? 1 : 0.5
                            Behavior on width  { NumberAnimation { duration: 120 } }
                            Behavior on height { NumberAnimation { duration: 120 } }
                            Text {
                                visible: vWsItem.active
                                anchors.centerIn: parent
                                text: vWsItem.wsId
                                font.pixelSize: BarConfig.sp(9); font.weight: Font.Medium
                                color: Colors.primary
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: Hyprland.dispatch("workspace " + vWsItem.wsId)
                            }
                        }
                    }
                }
            }
        }

        // Center: clock
        Column {
            anchors.centerIn: parent
            spacing: 2

            Text {
                visible: BarConfig.showClock
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(new Date(), "HH\nmm")
                color: Colors.colOnSurface
                font.pixelSize: BarConfig.barFontSize
                horizontalAlignment: Text.AlignHCenter
                Timer {
                    interval: 10000; running: BarConfig.isVertical && BarConfig.showClock
                    repeat: true; triggeredOnStart: true
                    onTriggered: parent.text = Qt.formatTime(new Date(), "HH\nmm")
                }
            }
        }

        // Bottom section: notif + settings + power
        Column {
            anchors { bottom: parent.bottom; bottomMargin: 10; horizontalCenter: parent.horizontalCenter }
            spacing: 8

            // Notification bell
            Item {
                implicitWidth: BarConfig.sp(22); implicitHeight: BarConfig.sp(22)
                anchors.horizontalCenter: parent.horizontalCenter
                visible: BarConfig.showNotifications !== false
                Text {
                    anchors.centerIn: parent; text: ""
                    font.family: "Symbols Nerd Font Mono"; font.pixelSize: BarConfig.sp(13)
                    color: NotificationService.unreadCount > 0 ? Colors.primary : Colors.colOnSurfaceVariant
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                Rectangle {
                    visible: NotificationService.unreadCount > 0
                    width: 7; height: 7; radius: 3.5; color: Colors.primary
                    anchors { top: parent.top; right: parent.right; topMargin: 2; rightMargin: 1 }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleNotifications() }
            }

            // Settings / Control Centre
            Item {
                implicitWidth: BarConfig.sp(22); implicitHeight: BarConfig.sp(22)
                anchors.horizontalCenter: parent.horizontalCenter
                Text {
                    anchors.centerIn: parent; text: "⚙"
                    font.pixelSize: BarConfig.barFontSize + 2
                    color: BarConfig.currentPopup !== "" && BarConfig.currentPopupScreen === barContent.barScreenName ? Colors.primary : Colors.colOnSurfaceVariant
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.togglePopup("controlcenter", barContent.barScreenName) }
            }

            // Power
            Item {
                implicitWidth: BarConfig.sp(22); implicitHeight: BarConfig.sp(22)
                anchors.horizontalCenter: parent.horizontalCenter
                Text {
                    anchors.centerIn: parent; text: ""
                    font.family: "Symbols Nerd Font Mono"; font.pixelSize: BarConfig.sp(12)
                    color: Colors.colOnSurfaceVariant
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.togglePopup("power", barContent.barScreenName) }
            }
        }
    }

    // ── Horizontal layout — existing content ─────────────────────────────
    Item {
        visible: !BarConfig.isVertical
        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }

        // ── Left ─────────────────────────────────────────────────────────
        Row {
            id: leftSection
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            // Drawer toggle icon
            Item {
                implicitWidth: BarConfig.sp(20); implicitHeight: BarConfig.sp(22)
                Text {
                    anchors.centerIn: parent; text: "\uF0C9"
                    font.family: "Symbols Nerd Font Mono"; font.pixelSize: BarConfig.sp(12)
                    color: ShellState.drawerOpen ? Colors.primary : Colors.colOnSurfaceVariant
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { BarConfig.closePopup(); ShellState.toggleDrawer() } }
            }

            Repeater {
                model: BarConfig.leftWidgets
                WidgetSlot {
                    required property string modelData
                    widgetId: modelData
                    barScreenName: barContent.barScreenName
                }
            }
        }

        // ── Centre ───────────────────────────────────────────────────────
        Item {
            anchors.centerIn: parent
            implicitWidth: centerRow.implicitWidth
            height: parent.height

            Row {
                id: centerRow
                anchors.centerIn: parent
                spacing: 12

                Repeater {
                    model: BarConfig.centerWidgets
                    WidgetSlot {
                        required property string modelData
                        widgetId: modelData
                        barScreenName: barContent.barScreenName
                    }
                }
            }
        }

        // ── Right ────────────────────────────────────────────────────────
        Row {
            id: rightSection
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Repeater {
                model: BarConfig.rightWidgets
                WidgetSlot {
                    required property string modelData
                    widgetId: modelData
                    barScreenName: barContent.barScreenName
                }
            }

            // Launcher icon
            Item {
                implicitWidth: BarConfig.sp(20); implicitHeight: BarConfig.sp(22)
                Text {
                    anchors.centerIn: parent; text: "\uF00A"
                    font.family: "Symbols Nerd Font Mono"; font.pixelSize: BarConfig.sp(12)
                    color: ShellState.launcherOpen ? Colors.primary : Colors.colOnSurfaceVariant
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleLauncher() }
            }

            SettingsGear {
                barScreenName: barContent.barScreenName
            }

            // Power icon — opens power menu
            Item {
                implicitWidth: BarConfig.sp(20); implicitHeight: BarConfig.sp(22)
                Text {
                    anchors.centerIn: parent
                    text: "\uF011"
                    font.family: "Symbols Nerd Font Mono"
                    color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.sp(11)
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: BarConfig.togglePopup("power", barContent.barScreenName)
                }
            }
        }
    }

    component BarDivider: Item {
        implicitWidth: 1; implicitHeight: 22
        Rectangle {
            width: 1; height: 14
            anchors.centerIn: parent
            color: Colors.popupBorder; opacity: 0.7
        }
    }
}
