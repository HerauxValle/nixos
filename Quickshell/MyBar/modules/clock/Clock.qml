import QtQuick
import "../../config"
import "../../services"

Item {
    id: root
    implicitWidth: lbl.implicitWidth
    implicitHeight: 22

    property string timeStr: Qt.formatTime(new Date(), "hh:mm AP")

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.timeStr = Qt.formatTime(new Date(), "hh:mm AP")
    }

    Text {
        id: lbl
        anchors.centerIn: parent
        text: root.timeStr
        color: Colors.colOnSurface
        font.pixelSize: BarConfig.barFontSize
        font.weight: Font.Medium
        opacity: 0.9
    }

    // Click clock to toggle Left Drawer (which has the calendar)
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: ShellState.toggleDrawer()
    }
}
