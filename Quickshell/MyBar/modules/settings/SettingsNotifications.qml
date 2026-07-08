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
    component SRow: Item {
        id: sr; required property string label; default property alias children: srR.data
        width: parent?.width ?? 400; implicitHeight: 36
        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: sr.label; color: Colors.colOnSurface; font.pixelSize: 12 }
        Item { id: srR; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
               implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
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

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 32; clip: true
        Column {
            id: col; width: parent.width - 48; x: 24; y: 20; spacing: 10

            SLabel { text: "NOTIFICATION FEED" }

            Item {
                width: parent.width; height: 40
                Row {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 12

                    Text {
                        text: NotificationService.unreadCount + " unread"
                        color: NotificationService.unreadCount > 0 ? Colors.primary : Colors.colOnSurfaceVariant
                        font.pixelSize: 13
                    }

                    Rectangle {
                        width: 90; height: 28; radius: 14
                        color: Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.15)
                        border.color: Colors.error; border.width: 1
                        visible: NotificationService.notifications.length > 0
                        Text { anchors.centerIn: parent; text: "Clear All"
                               color: Colors.error; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: NotificationService.dismissAll() }
                    }
                }
            }

            HR {}
            SLabel { text: "RECENT NOTIFICATIONS" }

            Text {
                visible: NotificationService.notifications.length === 0
                text: "No notifications yet"
                color: Colors.colOnSurfaceVariant; font.pixelSize: 12; opacity: 0.6
            }

            Column {
                width: parent.width; spacing: 4

                Repeater {
                    model: Math.min(NotificationService.notifications.length, 10)
                    Item {
                        required property int index
                        readonly property var notif: NotificationService.notifications[index] ?? null
                        width: parent?.width ?? 400; implicitHeight: notifBox.implicitHeight

                        Rectangle {
                            id: notifBox
                            anchors { left: parent.left; right: parent.right }
                            radius: 10; color: Colors.surfaceContainerHigh
                            implicitHeight: notifCol.implicitHeight + 16

                            Column {
                                id: notifCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                                spacing: 3

                                Row {
                                    width: parent.width; spacing: 6
                                    Text { text: notif ? notif.app : ""; color: Colors.primary
                                           font.pixelSize: 10; font.weight: Font.Medium
                                           width: parent.width - 60; elide: Text.ElideRight }
                                    Text { text: notif ? notif.timestamp : ""
                                           color: Colors.colOnSurfaceVariant; font.pixelSize: 9 }
                                }
                                Text { text: notif ? notif.summary : ""; color: Colors.colOnSurface
                                       font.pixelSize: 12; wrapMode: Text.WordWrap
                                       width: parent.width - 24 }
                                Text { text: notif ? notif.body : ""; color: Colors.colOnSurfaceVariant
                                       font.pixelSize: 10; wrapMode: Text.WordWrap
                                       visible: notif && notif.body !== ""; width: parent.width - 24 }
                            }
                        }
                    }
                }
            }
            Item { height: 8 }
        }
    }
}
