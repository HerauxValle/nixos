pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../../config"

Item {
    id: root
    clip: true

    property int blurStrength: 8

    Process {
        id: blurProc
        command: ["hyprctl", "keyword", "decoration:blur:size", String(root.blurStrength)]
    }

    component SLabel: Text {
        color: Colors.primary; font.pixelSize: 9
        font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.8
    }
    component HR: Rectangle {
        width: parent?.width ?? 400; height: 1; color: Colors.outlineVariant; opacity: 0.5
    }
    component SRow: Item {
        id: sr; required property string label; default property alias children: srR.data
        width: parent?.width ?? 400; implicitHeight: 36
        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: sr.label; color: Colors.colOnSurface; font.pixelSize: 12 }
        Item { id: srR; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
               implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
    }
    component SimpleSlider: Item {
        id: ssl; required property real minVal; required property real maxVal; required property real value
        signal moved(real v); implicitWidth: 150; implicitHeight: 20
        Rectangle {
            id: ssT; anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 4; radius: 2; color: Colors.outlineVariant
            Rectangle { width: (ssl.value - ssl.minVal) / (ssl.maxVal - ssl.minVal) * ssT.width
                        height: parent.height; radius: parent.radius; color: Colors.primary }
            Rectangle { width: 14; height: 14; radius: 7; color: Colors.primary
                        anchors.verticalCenter: parent.verticalCenter
                        x: (ssl.value - ssl.minVal) / (ssl.maxVal - ssl.minVal) * (ssT.width - width) }
        }
        MouseArea {
            anchors { fill: parent; topMargin: -8; bottomMargin: -8 }
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: (m) => { if (!pressed) return
                const p = mapToItem(ssT, m.x, m.y)
                ssl.moved(ssl.minVal + Math.max(0, Math.min(1, p.x / ssT.width)) * (ssl.maxVal - ssl.minVal)) }
            onClicked: (m) => { const p = mapToItem(ssT, m.x, m.y)
                ssl.moved(ssl.minVal + Math.max(0, Math.min(1, p.x / ssT.width)) * (ssl.maxVal - ssl.minVal)) }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width; contentHeight: col.implicitHeight + 32; clip: true

        Column {
            id: col; width: parent.width - 48; x: 24; y: 20; spacing: 10

            SLabel { text: "ACCENT PRESETS" }

            Row {
                spacing: 8
                Repeater {
                    model: BarConfig.tintPresets
                    Rectangle {
                        required property string modelData; required property int index
                        width: 28; height: 28; radius: 14; color: modelData
                        border.color: BarConfig.tintIndex === index ? "white" : "transparent"; border.width: 2
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: BarConfig.tintIndex = index }
                    }
                }
            }

            Item {
                width: parent.width; height: 36
                Row {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Text { text: "Custom hex:"; color: Colors.colOnSurfaceVariant; font.pixelSize: 11 }
                    Rectangle {
                        id: hexBox; width: 108; height: 28; radius: 6
                        color: Colors.surfaceContainerHigh
                        border.color: hexInput.activeFocus ? Colors.primary : Colors.outline; border.width: 1
                        TextInput {
                            id: hexInput; anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            verticalAlignment: TextInput.AlignVCenter
                            text: Colors.primary.toString().toUpperCase().substring(0, 7)
                            color: Colors.colOnSurface; font.pixelSize: 11; maximumLength: 7
                            selectByMouse: true; activeFocusOnPress: true
                            Keys.onReturnPressed: applyHex()
                            function applyHex() {
                                const h = text.trim()
                                if (/^#[0-9A-Fa-f]{6}$/.test(h)) Colors.primary = Qt.color(h)
                            }
                        }
                    }
                    Rectangle {
                        width: 48; height: 28; radius: 14; color: Colors.primary
                        Text { anchors.centerIn: parent; text: "Apply"; font.pixelSize: 10; color: Colors.colOnPrimary }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: hexInput.applyHex() }
                    }
                }
            }

            HR {}
            SLabel { text: "OPACITY & BLUR" }

            SRow {
                label: "Bar Opacity"
                Row {
                    spacing: 8
                    SimpleSlider { minVal: 0.3; maxVal: 1.0; value: BarConfig.barOpacity
                                   onMoved: (v) => BarConfig.barOpacity = Math.round(v * 100) / 100
                                   anchors.verticalCenter: parent.verticalCenter }
                    Text { text: Math.round(BarConfig.barOpacity * 100) + "%"; color: Colors.colOnSurfaceVariant
                           font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                }
            }

            SRow {
                label: "Blur Strength"
                Row {
                    spacing: 8
                    SimpleSlider { minVal: 0; maxVal: 20; value: root.blurStrength
                                   onMoved: (v) => { root.blurStrength = Math.round(v)
                                       blurProc.command = ["hyprctl", "keyword", "decoration:blur:size", String(Math.round(v))]
                                       blurProc.running = true }
                                   anchors.verticalCenter: parent.verticalCenter }
                    Text { text: String(Math.round(root.blurStrength)); color: Colors.colOnSurfaceVariant
                           font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                }
            }

            HR {}
            SLabel { text: "TYPOGRAPHY" }

            SRow {
                label: "Font Size"
                Row {
                    spacing: 8
                    SimpleSlider { minVal: 10; maxVal: 18; value: BarConfig.barFontSize
                                   onMoved: (v) => BarConfig.barFontSize = Math.round(v)
                                   anchors.verticalCenter: parent.verticalCenter }
                    Text { text: BarConfig.barFontSize + "px"; color: Colors.colOnSurfaceVariant
                           font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                }
            }

            HR {}
            SLabel { text: "THEME NOTE" }
            Text {
                width: parent.width
                text: "Set AETHERA_* env vars in themes/*.env
Reload via qsr (or Super+R)"
                color: Colors.colOnSurfaceVariant; font.pixelSize: 10; opacity: 0.7; wrapMode: Text.WordWrap
            }
            Item { height: 8 }
        }
    }
}
