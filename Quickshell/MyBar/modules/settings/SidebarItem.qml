pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Item {
    id: sideItem
    required property int    sectionIndex
    required property string icon
    required property string label
    required property bool   active
    signal selected()

    width: parent?.width ?? 196
    implicitHeight: 40

    Rectangle {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 2; bottomMargin: 2 }
        radius: 10
        color: sideItem.active
               ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18)
               : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 10

            Text {
                text: sideItem.icon
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: 14
                color: sideItem.active ? Colors.primary : Colors.colOnSurfaceVariant
                width: 18; horizontalAlignment: Text.AlignHCenter
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            Text {
                text: sideItem.label
                font.pixelSize: 12
                color: sideItem.active ? Colors.primary : Colors.colOnSurface
                font.weight: sideItem.active ? Font.Medium : Font.Normal
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sideItem.selected()
        }
    }
}
