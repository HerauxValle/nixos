pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../../config"

// Shows active MPRIS track with transport controls: ⏮ title ⏸ ⏭
Item {
    id: root
    implicitWidth:  visible ? Math.min(row.implicitWidth, 200) : 0
    implicitHeight: 22
    visible:  activePlayer !== null
    opacity:  activePlayer !== null ? 1 : 0
    clip: true
    Behavior on opacity { NumberAnimation { duration: 250; easing.bezierCurve: Colors.standard } }
    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.bezierCurve: Colors.standard } }

    readonly property MprisPlayer activePlayer: {
        const vals = Mpris.players.values
        const playing = vals.find(p => p.isPlaying)
        if (playing) return playing
        return vals.find(p => p.playbackState === MprisPlaybackState.Paused) ?? null
    }

    Row {
        id: row
        spacing: 4
        anchors.left:            parent.left
        anchors.verticalCenter:  parent.verticalCenter

        // \uF04A = previous
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: BarConfig.sp(10)
            font.family: "Symbols Nerd Font Mono"
            color: root.activePlayer?.canGoPrevious ?? false
                   ? Colors.colOnSurfaceVariant : Colors.outline
            text: "\uF04A"
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: root.activePlayer?.previous()
            }
        }

        // Title — Artist (scrolling clip)
        Item {
            width: Math.min(lbl.implicitWidth, 120)
            height: lbl.implicitHeight
            clip: true
            anchors.verticalCenter: parent.verticalCenter
            Text {
                id: lbl
                color: Colors.colOnSurface
                font.pixelSize: BarConfig.sp(11)
                text: {
                    const p = root.activePlayer
                    if (!p) return ""
                    const t = p.trackTitle  || ""
                    const a = p.trackArtist || ""
                    return a ? t + " \u2014 " + a : t
                }
            }
        }

        // \uF04C = pause  \uF04B = play
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: BarConfig.sp(10)
            font.family: "Symbols Nerd Font Mono"
            color: Colors.primary
            text: root.activePlayer?.isPlaying ? "\uF04C" : "\uF04B"
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: root.activePlayer?.togglePlaying()
            }
        }

        // \uF051 = next
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: BarConfig.sp(10)
            font.family: "Symbols Nerd Font Mono"
            color: root.activePlayer?.canGoNext ?? false
                   ? Colors.colOnSurfaceVariant : Colors.outline
            text: "\uF051"
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: root.activePlayer?.next()
            }
        }
    }
}
