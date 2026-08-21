pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

// Volume popup — slider, mute, sink name.
Rectangle {
    id: root
    implicitWidth: BarConfig.sp(300)
    implicitHeight: col.implicitHeight + 28
    radius: BarConfig.sp(14)
    color: Colors.popupBg
    border.color: Colors.popupBorder
    border.width: 1

    component VSlider: Item {
        id: sl
        required property real value
        required property real maxVal
        signal moved(real v)

        implicitWidth: BarConfig.sp(200); implicitHeight: BarConfig.sp(20)

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: BarConfig.sp(4); radius: BarConfig.sp(2)
            color: Colors.surfaceContainerHigh

            Rectangle {
                width: Math.min(sl.value / sl.maxVal, 1) * track.width
                height: parent.height; radius: parent.radius
                color: sl.value > 1.0 ? Colors.error : Colors.primary
                Behavior on width { NumberAnimation { duration: 60 } }
            }

            Rectangle {
                id: knob
                width: BarConfig.sp(16); height: BarConfig.sp(16); radius: BarConfig.sp(8)
                color: Colors.primary
                anchors.verticalCenter: parent.verticalCenter
                x: Math.min(sl.value / sl.maxVal, 1) * (track.width - width)
                Behavior on x { NumberAnimation { duration: 60 } }
            }

            MouseArea {
                // Extend hit area vertically but NOT horizontally to avoid x offset.
                // Use mapToItem to get coordinates in the track's local space.
                anchors { fill: parent; topMargin: -10; bottomMargin: -10 }
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: (m) => {
                    if (!pressed) return
                    const p = mapToItem(track, m.x, m.y)
                    sl.moved(Math.max(0, Math.min(sl.maxVal, (p.x / track.width) * sl.maxVal)))
                }
                onClicked: (m) => {
                    const p = mapToItem(track, m.x, m.y)
                    sl.moved(Math.max(0, Math.min(sl.maxVal, (p.x / track.width) * sl.maxVal)))
                }
            }
        }
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: BarConfig.sp(16) }
        spacing: BarConfig.sp(12)

        // ── Header row ──
        Row {
            width: parent.width
            Text {
                text: "Volume"
                color: Colors.colOnSurface
                font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { width: parent.width - muteBtn.implicitWidth - 60; height: 1 }
            Item {
                id: muteBtn
                implicitWidth: BarConfig.sp(58); implicitHeight: BarConfig.sp(24)
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.fill: parent; radius: height / 2
                    color: Audio.muted ? Colors.error : Colors.secondaryContainer
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Text {
                        anchors.centerIn: parent
                        text: Audio.muted ? "Unmute" : "Mute"
                        color: Audio.muted ? "white" : Colors.colOnSurfaceVariant
                        font.pixelSize: BarConfig.fsSm
                    }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Audio.toggleMute() }
            }
        }

        // ── Slider row ──
        Row {
            width: parent.width; spacing: BarConfig.sp(10)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: BarConfig.fsMd; font.family: "Symbols Nerd Font Mono"
                color: Audio.muted ? Colors.outline : Colors.primary
                // \uF026 off  \uF027 down  \uF028 up
                text: Audio.muted ? "\uF026" : Audio.volume > 0.5 ? "\uF028" : "\uF027"
                Behavior on color { ColorAnimation { duration: 160 } }
            }
            VSlider {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: parent.width - 70
                value: Audio.volume
                maxVal: 1.5
                onMoved: (v) => Audio.setVolume(v)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Audio.volume * 100) + "%"
                color: Colors.colOnSurfaceVariant
                font.pixelSize: BarConfig.fsMd; width: 34; horizontalAlignment: Text.AlignRight
            }
        }

        // ── Sink name ──
        Text {
            text: Audio.sinkName
            color: Colors.colOnSurfaceVariant
            font.pixelSize: BarConfig.fsSm; opacity: 0.7
        }
    }
}
