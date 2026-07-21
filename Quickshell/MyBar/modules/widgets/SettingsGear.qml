import QtQuick
import "../../config"

Item {
    property string barScreenName: ""
    implicitWidth: 22; implicitHeight: 22

    Text {
        // Same story as the drawer hamburger glyph in BarContent.qml -- fill
        // + AlignVCenter centers by the font's actual baseline metrics
        // instead of this Text's implicit ascent/descent bounding box, which
        // is what icon-font generators design glyphs against.
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
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
