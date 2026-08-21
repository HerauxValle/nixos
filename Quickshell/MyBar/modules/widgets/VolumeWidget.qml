pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../config"
import "../../services"

Item {
    id: root
    required property string barScreenName
    implicitWidth: row.implicitWidth
    implicitHeight: 22

    Row {
        id: row
        spacing: 5
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        // Mute/icon — left-click opens CC, right-click mutes
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: BarConfig.sp(11); font.family: "Symbols Nerd Font Mono"
            color: Audio.muted ? Colors.outline : Colors.primary
            text: Audio.muted        ? "\uF026"
                : Audio.volume > 0.5 ? "\uF028"
                :                      "\uF027"
            Behavior on color { ColorAnimation { duration: 100 } }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (e) => {
                    if (e.button === Qt.RightButton) BarConfig.togglePopup("controlcenter", barScreenName)
                    else { Audio.toggleMute(); OsdState.showVolume(Audio.volume, !Audio.muted) }
                }
            }
        }

        // Compact inline slider (48 px)
        Item {
            id: slArea
            width: 48; height: 22
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: slTrack
                height: 3; radius: 2
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                color: Colors.outlineVariant
                opacity: Audio.muted ? 0.4 : 1
                Behavior on opacity { NumberAnimation { duration: 100 } }

                Rectangle {
                    width: Math.min(Audio.volume, 1.0) * slTrack.width
                    height: parent.height; radius: parent.radius
                    color: Colors.primary
                    Behavior on width { NumberAnimation { duration: 60 } }
                }
                Rectangle {
                    id: slKnob
                    width: 9; height: 9; radius: 5; color: Colors.primary
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.min(Audio.volume, 1.0) * (slTrack.width - width)
                    Behavior on x { NumberAnimation { duration: 60 } }
                }
            }

            MouseArea {
                anchors { fill: parent; topMargin: -7; bottomMargin: -7 }
                cursorShape: Qt.SizeHorCursor
                onPositionChanged: (m) => {
                    if (!pressed) return
                    const p = mapToItem(slTrack, m.x, m.y)
                    Audio.setVolume(Math.max(0, Math.min(1.0, p.x / slTrack.width)))
                }
                onClicked: (m) => {
                    const p = mapToItem(slTrack, m.x, m.y)
                    Audio.setVolume(Math.max(0, Math.min(1.0, p.x / slTrack.width)))
                }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (e) => Audio.changeVolume(e.angleDelta.y > 0 ? 0.05 : -0.05)
                }
            }
        }
    }
}
