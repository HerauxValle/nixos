pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"

Item {
    id: root
    clip: true

    property int sinkIdx: {
        const idx = Audio.allSinks.findIndex(s => s === Audio.pwSink)
        return idx < 0 ? 0 : idx
    }
    property int srcIdx: {
        const idx = Audio.allSources.findIndex(s => s === Audio.pwSource)
        return idx < 0 ? 0 : idx
    }

    component SLabel: Text {
        color: Colors.primary; font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.8
    }
    component HR: Rectangle { width: parent?.width ?? 400; height: 1; color: Colors.outlineVariant; opacity: 0.5 }

    component VSlider: Item {
        id: sl; required property real value; required property real maxVal
        signal moved(real v); implicitHeight: 20
        Rectangle {
            id: slT; anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 5; radius: 3; color: Colors.surfaceContainerHigh
            Rectangle { width: Math.min(sl.value / sl.maxVal, 1) * slT.width
                        height: parent.height; radius: parent.radius
                        color: sl.value > 1.0 ? Colors.error : Colors.primary
                        Behavior on width { NumberAnimation { duration: 50 } } }
            Rectangle { width: 16; height: 16; radius: 8; color: Colors.primary
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.min(sl.value / sl.maxVal, 1) * (slT.width - width)
                        Behavior on x { NumberAnimation { duration: 50 } } }
        }
        MouseArea {
            anchors { fill: parent; topMargin: -10; bottomMargin: -10 }; cursorShape: Qt.PointingHandCursor
            onPositionChanged: (m) => { if (!pressed) return; const p = mapToItem(slT, m.x, m.y)
                sl.moved(Math.max(0, Math.min(sl.maxVal, (p.x / slT.width) * sl.maxVal))) }
            onClicked: (m) => { const p = mapToItem(slT, m.x, m.y)
                sl.moved(Math.max(0, Math.min(sl.maxVal, (p.x / slT.width) * sl.maxVal))) }
        }
    }

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 32; clip: true
        Column {
            id: col; width: parent.width - 48; x: 24; y: 20; spacing: 10

            SLabel { text: "MASTER VOLUME" }

            Item {
                width: parent.width; height: 36
                Text {
                    id: vIco
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    font.family: "Symbols Nerd Font Mono"; font.pixelSize: 16
                    color: Audio.muted ? Colors.outline : Colors.primary
                    text: Audio.muted ? "" : Audio.volume > 0.5 ? "" : ""
                    Behavior on color { ColorAnimation { duration: 100 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Audio.toggleMute() }
                }
                VSlider {
                    anchors { left: vIco.right; leftMargin: 12; right: vPct.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    value: Audio.volume; maxVal: 1.5
                    onMoved: (v) => Audio.setVolume(v)
                }
                Text {
                    id: vPct
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 38; horizontalAlignment: Text.AlignRight
                    text: Math.round(Audio.volume * 100) + "%"
                    color: Colors.colOnSurfaceVariant; font.pixelSize: 11
                }
            }

            HR {}
            SLabel { text: "OUTPUT DEVICE" }

            Column {
                width: parent.width; spacing: 2
                Repeater {
                    model: Audio.allSinks.length
                    Item {
                        required property int index
                        readonly property var sink: Audio.allSinks[index] ?? null
                        width: parent?.width ?? 400; height: 40
                        Rectangle {
                            anchors.fill: parent; radius: 10
                            color: root.sinkIdx === index
                                   ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.15)
                                   : Colors.surfaceContainerHigh
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row {
                                anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 8
                                Text { text: root.sinkIdx === index ? "✓" : " "
                                       color: Colors.primary; font.pixelSize: 12; width: 14 }
                                Text { text: sink ? (sink.description || sink.name || "Unknown").replace(/\s*\[.*?\]/g, "").trim() : ""
                                       color: Colors.colOnSurface; font.pixelSize: 11; elide: Text.ElideRight
                                       width: parent.width - 34 }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: Audio.setDefaultSink(Audio.allSinks[index]) }
                        }
                    }
                }
            }

            HR {}
            SLabel { text: "INPUT DEVICE" }

            Column {
                width: parent.width; spacing: 2
                Repeater {
                    model: Audio.allSources.length
                    Item {
                        required property int index
                        readonly property var src: Audio.allSources[index] ?? null
                        width: parent?.width ?? 400; height: 40
                        Rectangle {
                            anchors.fill: parent; radius: 10
                            color: root.srcIdx === index
                                   ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.15)
                                   : Colors.surfaceContainerHigh
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row {
                                anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 8
                                Text { text: root.srcIdx === index ? "✓" : " "
                                       color: Colors.primary; font.pixelSize: 12; width: 14 }
                                Text { text: src ? (src.description || src.name || "Unknown").replace(/\s*\[.*?\]/g, "").trim() : ""
                                       color: Colors.colOnSurface; font.pixelSize: 11; elide: Text.ElideRight
                                       width: parent.width - 34 }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: Audio.setDefaultSource(Audio.allSources[index]) }
                        }
                    }
                }
            }

            Item { height: 8 }
        }
    }
}
