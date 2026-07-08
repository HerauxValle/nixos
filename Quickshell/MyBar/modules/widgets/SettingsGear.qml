import QtQuick
import "../../config"

Item {
    property string barScreenName: ""
    implicitWidth: 22; implicitHeight: 22

    Text {
        anchors.centerIn: parent
        text: "\uF013"
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: BarConfig.sp(13)
        color: BarConfig.currentPopup !== "" && BarConfig.currentPopupScreen === barScreenName ? Colors.primary : Colors.colOnSurfaceVariant
        rotation: BarConfig.currentPopup !== "" && BarConfig.currentPopupScreen === barScreenName ? 30 : 0
        Behavior on rotation { NumberAnimation { duration: 200; easing.bezierCurve: Colors.spring } }
        Behavior on color    { ColorAnimation  { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: BarConfig.togglePopup("controlcenter", barScreenName)
    }
}
