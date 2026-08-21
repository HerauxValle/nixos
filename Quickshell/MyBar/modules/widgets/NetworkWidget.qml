pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Networking
import "../../config"
import "../../services"

Item {
    id: root
    implicitWidth: ico.implicitWidth + 2
    implicitHeight: 22

    readonly property bool connected:
        Networking.connectivity === NetworkConnectivity.Full ||
        Networking.connectivity === NetworkConnectivity.Limited

    Text {
        id: ico
        anchors.centerIn: parent
        font.pixelSize: BarConfig.sp(12); font.family: "Symbols Nerd Font Mono"
        color: root.connected ? Colors.primary : Colors.outline
        text: root.connected ? "\uF1EB" : "\uF127"
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: BarConfig.togglePopup("wifi", barScreenName)
        acceptedButtons: Qt.LeftButton
    }
}
