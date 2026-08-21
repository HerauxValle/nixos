pragma ComponentBehavior: Bound
import QtQuick
import "../../config"
import "../../services"

// Delegate for a single Bluetooth device row.
// mode: "connected" | "paired" | "discovered"
Rectangle {
    id: root
    required property var modelData
    required property int index
    property string mode: "paired"

    width: parent?.width ?? 300
    height: BarConfig.sp(44)
    radius: BarConfig.sp(10)

    color: mode === "connected"
           ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.12)
           : Colors.surfaceContainerHigh
    border.color: mode === "connected" ? Colors.primary : "transparent"
    border.width: mode === "connected" ? 1 : 0

    signal connectRequested(string mac)
    signal disconnectRequested(string mac)

    Item {
        anchors { left: parent.left; right: parent.right
                  leftMargin: BarConfig.sp(12); rightMargin: BarConfig.sp(12)
                  top: parent.top; bottom: parent.bottom }

        Text {
            id: iconText
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            font.pixelSize: BarConfig.fsLg
            font.family: "Symbols Nerd Font Mono"
            color: root.mode === "connected" ? Colors.primary : Colors.colOnSurfaceVariant
            text: ""
        }

        Text {
            id: nameText
            anchors { left: iconText.right; leftMargin: BarConfig.sp(10); verticalCenter: parent.verticalCenter }
            text: root.modelData.name !== "" ? root.modelData.name : root.modelData.mac
            color: Colors.colOnSurface
            font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
            elide: Text.ElideRight
            width: BarConfig.sp(160)
        }

        Rectangle {
            id: actionBtn
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: root.mode === "connected" ? 78 : 64
            height: BarConfig.sp(26); radius: BarConfig.sp(13)
            visible: root.mode !== "discovered" || true

            color: root.mode === "connected"
                   ? Colors.surfaceContainerHigh
                   : Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.2)
            border.color: root.mode === "connected" ? Colors.outline : Colors.primary
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: root.mode === "connected" ? "Disconnect"
                      : root.mode === "discovered" ? "Pair" : "Connect"
                color: root.mode === "connected" ? Colors.colOnSurfaceVariant : Colors.primary
                font.pixelSize: BarConfig.fsSm
            }

            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.mode === "connected")
                        root.disconnectRequested(root.modelData.mac)
                    else
                        root.connectRequested(root.modelData.mac)
                }
            }
        }
    }
}
