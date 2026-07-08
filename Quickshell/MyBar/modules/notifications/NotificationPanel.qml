pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"

Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: notifWin
            required property ShellScreen modelData
            screen: modelData

            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:mybar-notifications"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            // Right-strip only — window does NOT cover the bar bell icon on the left
            anchors.top: true
            anchors.bottom: true
            anchors.left: false
            anchors.right: true
            exclusiveZone: 0
            implicitWidth: 320 + (BarConfig.fillMode === "pill" ? BarConfig.barMargin : 0) + 4
            readonly property int _sw: screen?.width ?? 1920
            readonly property int _sh: screen?.height ?? 1080
            visible: ShellState.notificationsOpen



            Rectangle {
                id: panelRect
                width: notifWin.implicitWidth - 4
                // Same geometry as drawer: respects bar edge + vMargin for pill/hanging
                readonly property int _barEdge: (BarConfig.barPosition === "top" ? BarConfig.barHeight : 0)
                readonly property int _barEdgeB: (BarConfig.barPosition === "bottom" ? BarConfig.barHeight : 0)
                readonly property int _maxH: Math.min(notifWin._sh - _barEdge - _barEdgeB - 24, 720)
                y: _barEdge + Math.max(8, (notifWin._sh - _barEdge - _barEdgeB - _maxH) / 2)
                height: _maxH
                readonly property int _hMargin: BarConfig.fillMode === "pill" ? BarConfig.barMargin : 0
                // window is already right-anchored; panel sits at left+hMargin of window
                x: _hMargin
                // Same style as drawer: color, border, corner logic
                color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)
                border.color: Colors.popupBorder
                border.width: 1
                readonly property real _r: 14
                readonly property bool _pill: BarConfig.fillMode === "pill"
                // Right panel: right edge flush (square), left side open (round); pill: all round
                topLeftRadius:     _r
                topRightRadius:    _pill ? _r : 0
                bottomLeftRadius:  _r
                bottomRightRadius: _pill ? _r : 0
                MouseArea { anchors.fill: parent; onClicked: {} }

                Item {
                    id: header
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: BarConfig.sp(44)

                    Text {
                        id: titleLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: BarConfig.sp(14)
                        text: "NOTIFICATIONS"
                        color: Colors.colOnSurfaceVariant
                        font.pixelSize: BarConfig.fsSm
                        font.weight: Font.Medium
                        font.letterSpacing: 1.2
                    }
                    Rectangle {
                        anchors.left: titleLabel.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: BarConfig.sp(6)
                        visible: NotificationService.unreadCount > 0
                        width: Math.max(18, badgeText.implicitWidth + 8)
                        height: BarConfig.sp(18)
                        radius: BarConfig.sp(9)
                        color: Colors.primary
                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: NotificationService.unreadCount
                            color: Colors.colOnPrimary
                            font.pixelSize: BarConfig.fsSm
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        anchors.right: closeBtn.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: BarConfig.sp(10)
                        text: "Clear"
                        color: Colors.primary
                        font.pixelSize: BarConfig.fsMd
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NotificationService.dismissAll() }
                    }
                    Text {
                        id: closeBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: BarConfig.sp(12)
                        text: "×"
                        color: Colors.colOnSurfaceVariant
                        font.pixelSize: Math.round(18 * BarConfig.uiScale)
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.closeNotifications() }
                    }
                }

                Rectangle {
                    id: divider
                    anchors.top: header.bottom
                    anchors.left: parent.left; anchors.leftMargin: BarConfig.sp(14)
                    anchors.right: parent.right; anchors.rightMargin: BarConfig.sp(14)
                    height: 1
                    color: Colors.popupBorder; opacity: 0.7
                }

                Item {
                    anchors.top: divider.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: NotificationService.notifications.length === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: BarConfig.sp(24)
                        text: "No notifications"
                        color: Colors.colOnSurfaceVariant
                        font.pixelSize: BarConfig.fsMd
                    }
                }

                Flickable {
                    anchors.top: divider.bottom
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: BarConfig.sp(4)
                    anchors.bottomMargin: BarConfig.sp(8)
                    clip: true
                    contentHeight: listCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    visible: NotificationService.notifications.length > 0

                    Column {
                        id: listCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: BarConfig.sp(8)
                        anchors.rightMargin: BarConfig.sp(8)
                        spacing: BarConfig.sp(6)
                        topPadding: 4

                        Repeater {
                            model: NotificationService.notifications

                            delegate: Rectangle {
                                required property int index
                                required property var modelData
                                width: listCol.width
                                height: cardCol.implicitHeight + 20
                                radius: BarConfig.sp(8)
                                color: Colors.surfaceContainerHigh
                                border.color: Colors.popupBorder
                                border.width: 1

                                Column {
                                    id: cardCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: BarConfig.sp(12)
                                    anchors.rightMargin: BarConfig.sp(32)
                                    anchors.topMargin: BarConfig.sp(10)
                                    spacing: BarConfig.sp(3)
                                    Text {
                                        width: parent.width
                                        text: modelData.app + "  ·  " + modelData.timestamp
                                        color: Colors.colOnSurfaceVariant
                                        font.pixelSize: BarConfig.fsSm
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: modelData.summary
                                        color: Colors.colOnSurface
                                        font.pixelSize: BarConfig.fs
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: modelData.body
                                        color: Colors.colOnSurfaceVariant
                                        font.pixelSize: BarConfig.fsMd
                                        elide: Text.ElideRight
                                        visible: modelData.body !== ""
                                    }
                                }
                                Text {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: BarConfig.sp(6)
                                    anchors.rightMargin: BarConfig.sp(8)
                                    text: "×"
                                    color: Colors.colOnSurfaceVariant
                                    font.pixelSize: BarConfig.fsLg
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NotificationService.dismiss(modelData.id) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
