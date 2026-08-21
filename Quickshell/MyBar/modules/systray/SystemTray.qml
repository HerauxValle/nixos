pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../config"
import "../../services"

// Renders one icon per status-notifier item.
// Left-click: activate().  Right-click: secondaryActivate() (app handles its menu).
Item {
    id: root
    implicitWidth: trayRow.implicitWidth
    implicitHeight: 22

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: 6

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayItem
                required property SystemTrayItem modelData

                implicitWidth: 18
                implicitHeight: 18

                // Badge: count of unread notifications whose app name fuzzy-matches this tray item
                readonly property int badgeCount: {
                    const itemId    = (trayItem.modelData.id    || "").toLowerCase()
                    const itemTitle = (trayItem.modelData.title || "").toLowerCase()
                    let count = 0
                    for (const n of NotificationService.notifications) {
                        const app = (n.app || "").toLowerCase()
                        if (app && (itemId.includes(app) || itemTitle.includes(app) || app.includes(itemId) || app.includes(itemTitle)))
                            count++
                    }
                    return count
                }

                IconImage {
                    anchors.fill: parent
                    source: trayItem.modelData.icon
                    implicitSize: 18
                }

                // Notification badge dot
                Rectangle {
                    visible: trayItem.badgeCount > 0
                    width:  trayItem.badgeCount > 9 ? 14 : 10
                    height: 10
                    radius: 5
                    color: Colors.primary
                    anchors { top: parent.top; right: parent.right; topMargin: -2; rightMargin: -2 }
                    Behavior on width { NumberAnimation { duration: 80 } }
                    Text {
                        anchors.centerIn: parent
                        text: trayItem.badgeCount > 9 ? "9+" : (trayItem.badgeCount > 1 ? trayItem.badgeCount : "")
                        font.pixelSize: 7; font.weight: Font.Bold
                        color: Colors.colOnPrimary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (event) => {
                        if (event.button === Qt.LeftButton)
                            trayItem.modelData.activate()
                        else
                            trayItem.modelData.secondaryActivate()
                    }
                }
            }
        }
    }
}
