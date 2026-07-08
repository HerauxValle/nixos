pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Item {
    id: root
    clip: true

    component SLabel: Text {
        color: Colors.primary; font.pixelSize: 9
        font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.8
    }
    component HR: Rectangle {
        width: parent?.width ?? 400; height: 1; color: Colors.outlineVariant; opacity: 0.5
    }
    component SRow: Item {
        id: sr; required property string label; default property alias children: srR.data
        width: parent?.width ?? 400; implicitHeight: 38
        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: sr.label; color: Colors.colOnSurface; font.pixelSize: 12 }
        Item { id: srR; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
               implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
    }
    component Btn: Rectangle {
        id: btn; required property string lbl; required property bool active; signal pick()
        implicitWidth: blbl.implicitWidth + 18; implicitHeight: 28; radius: height / 2
        color: btn.active ? Colors.primary : Colors.surfaceContainerHigh
        border.color: btn.active ? Colors.primary : Colors.outline; border.width: 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Text { id: blbl; anchors.centerIn: parent; text: btn.lbl
               color: btn.active ? Colors.colOnPrimary : Colors.colOnSurfaceVariant; font.pixelSize: 11 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: btn.pick() }
    }
    component Toggle: Item {
        id: tog; property bool checked: false; signal toggled(bool v)
        implicitWidth: 38; implicitHeight: 22
        Rectangle {
            anchors.fill: parent; radius: height / 2
            color: tog.checked ? Colors.primary : Colors.surfaceContainerHigh
            border.color: tog.checked ? Colors.primary : Colors.outline; border.width: 1
            Behavior on color { ColorAnimation { duration: 160 } }
            Rectangle {
                width: 16; height: 16; radius: 8; color: tog.checked ? Colors.colOnPrimary : Colors.outline
                anchors.verticalCenter: parent.verticalCenter
                x: tog.checked ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
                Behavior on color { ColorAnimation { duration: 160 } }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: { tog.checked = !tog.checked; tog.toggled(tog.checked) } }
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
            anchors { fill: parent; topMargin: -8; bottomMargin: -8 }; cursorShape: Qt.PointingHandCursor
            onPositionChanged: (m) => { if (!pressed) return; const p = mapToItem(ssT, m.x, m.y)
                ssl.moved(ssl.minVal + Math.max(0, Math.min(1, p.x / ssT.width)) * (ssl.maxVal - ssl.minVal)) }
            onClicked: (m) => { const p = mapToItem(ssT, m.x, m.y)
                ssl.moved(ssl.minVal + Math.max(0, Math.min(1, p.x / ssT.width)) * (ssl.maxVal - ssl.minVal)) }
        }
    }

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 32; clip: true
        Column {
            id: col; width: parent.width - 48; x: 24; y: 20; spacing: 10

            SLabel { text: "LAYOUT" }

            SRow {
                label: "Style"
                Row { spacing: 4
                    Btn { lbl: "Hug";   active: BarConfig.fillMode === "full";    onPick: BarConfig.fillMode = "full" }
                    Btn { lbl: "Hang";  active: BarConfig.fillMode === "hanging"; onPick: BarConfig.fillMode = "hanging" }
                    Btn { lbl: "Float"; active: BarConfig.fillMode === "pill";    onPick: BarConfig.fillMode = "pill" }
                }
            }

            SRow {
                label: "Position"
                Row { spacing: 4
                    Btn { lbl: "Top";    active: BarConfig.barPosition === "top";    onPick: BarConfig.barPosition = "top" }
                    Btn { lbl: "Bottom"; active: BarConfig.barPosition === "bottom"; onPick: BarConfig.barPosition = "bottom" }
                    Btn { lbl: "Left";   active: BarConfig.barPosition === "left";   onPick: BarConfig.barPosition = "left" }
                    Btn { lbl: "Right";  active: BarConfig.barPosition === "right";  onPick: BarConfig.barPosition = "right" }
                }
            }

            SRow {
                label: "Auto-hide"
                Toggle { checked: BarConfig.autoHide; onToggled: (v) => BarConfig.autoHide = v }
            }

            SRow {
                visible: BarConfig.fillMode === "pill"
                label: "Pill Align"
                Row { spacing: 4
                    Btn { lbl: "Left";   active: BarConfig.pillAlign === "left";   onPick: BarConfig.pillAlign = "left" }
                    Btn { lbl: "Center"; active: BarConfig.pillAlign === "center"; onPick: BarConfig.pillAlign = "center" }
                    Btn { lbl: "Right";  active: BarConfig.pillAlign === "right";  onPick: BarConfig.pillAlign = "right" }
                }
            }

            HR {}
            SLabel { text: "SIZING" }

            SRow {
                visible: BarConfig.fillMode === "pill"
                label: "Pill Width"
                Row { spacing: 8
                    SimpleSlider { minVal: 0.35; maxVal: 1.0; value: BarConfig.pillWidthPct
                                   onMoved: (v) => BarConfig.pillWidthPct = Math.round(v * 100) / 100
                                   anchors.verticalCenter: parent.verticalCenter }
                    Text { text: Math.round(BarConfig.pillWidthPct * 100) + "%"
                           color: Colors.colOnSurfaceVariant; font.pixelSize: 11
                           anchors.verticalCenter: parent.verticalCenter }
                }
            }

            SRow {
                label: "Height"
                Row { spacing: 8
                    SimpleSlider { minVal: 24; maxVal: 64; value: BarConfig.barHeight
                                   onMoved: (v) => BarConfig.barHeight = Math.round(v)
                                   anchors.verticalCenter: parent.verticalCenter }
                    Text { text: BarConfig.barHeight + "px"
                           color: Colors.colOnSurfaceVariant; font.pixelSize: 11
                           anchors.verticalCenter: parent.verticalCenter }
                }
            }

            SRow {
                label: "Opacity"
                Row { spacing: 8
                    SimpleSlider { minVal: 0.3; maxVal: 1.0; value: BarConfig.barOpacity
                                   onMoved: (v) => BarConfig.barOpacity = Math.round(v * 100) / 100
                                   anchors.verticalCenter: parent.verticalCenter }
                    Text { text: Math.round(BarConfig.barOpacity * 100) + "%"
                           color: Colors.colOnSurfaceVariant; font.pixelSize: 11
                           anchors.verticalCenter: parent.verticalCenter }
                }
            }

            Item { height: 8 }
        }
    }
}
