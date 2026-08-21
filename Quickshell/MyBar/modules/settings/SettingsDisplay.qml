pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../../config"

Item {
    id: root
    clip: true

    property string resolution: "Unknown"
    property real   brightness: 0.5
    property bool   nightMode:  false
    property string backlightPath: ""

    Component.onCompleted: {
        resProc.running        = true
        backlightProc.running  = true
    }

    Process {
        id: resProc
        command: ["bash", "-c", "xrandr --current 2>/dev/null | awk '/ connected.*[0-9]x[0-9]/{for(i=1;i<=NF;i++){if($i~/^[0-9]+x[0-9]+/){print $i; exit}}}' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: { if (text.trim() !== "") root.resolution = text.trim() }
        }
    }

    Process {
        id: backlightProc
        command: ["bash", "-c", "bl=$(ls /sys/class/backlight/ 2>/dev/null | head -1); [ -n \"$bl\" ] && max=$(cat /sys/class/backlight/$bl/max_brightness 2>/dev/null || echo 255) && cur=$(cat /sys/class/backlight/$bl/brightness 2>/dev/null || echo 128) && echo $bl|$max|$cur"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim()
                if (!line) return
                const parts = line.split("|")
                if (parts.length >= 3) {
                    root.backlightPath = "/sys/class/backlight/" + parts[0] + "/brightness"
                    const max = parseInt(parts[1]) || 255
                    const cur = parseInt(parts[2]) || 128
                    root.brightness = cur / max
                }
            }
        }
    }

    Process {
        id: brightnessProc
        property string path: root.backlightPath
        property int value: 128
        command: ["bash", "-c", "echo " + value + " | tee " + (path || "/dev/null") + " 2>/dev/null; brightnessctl set " + Math.round(root.brightness * 100) + "% 2>/dev/null"]
    }

    Process {
        id: gammastepOnProc
        command: ["bash", "-c", "pkill gammastep 2>/dev/null; gammastep -O 4000 &"]
    }
    Process {
        id: gammastepOffProc
        command: ["bash", "-c", "pkill gammastep 2>/dev/null; gammastep -x 2>/dev/null &"]
    }

    component SLabel: Text {
        color: Colors.primary; font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.8
    }
    component HR: Rectangle { width: parent?.width ?? 400; height: 1; color: Colors.outlineVariant; opacity: 0.5 }
    component InfoRow: Item {
        id: ir; required property string label; required property string value
        width: parent?.width ?? 400; height: 32
        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: ir.label; color: Colors.colOnSurfaceVariant; font.pixelSize: 12 }
        Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
               text: ir.value; color: Colors.colOnSurface; font.pixelSize: 12 }
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

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 32; clip: true
        Column {
            id: col; width: parent.width - 48; x: 24; y: 20; spacing: 10

            SLabel { text: "DISPLAY INFO" }
            InfoRow { label: "Resolution"; value: root.resolution }

            HR {}
            SLabel { text: "BRIGHTNESS" }

            Item {
                width: parent.width; height: 36
                Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                       text: "Brightness"; color: Colors.colOnSurface; font.pixelSize: 12 }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }; spacing: 8
                    SimpleSlider {
                        minVal: 0.02; maxVal: 1.0; value: root.brightness
                        onMoved: (v) => {
                            root.brightness = Math.round(v * 100) / 100
                            brightnessProc.running = true
                        }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text { text: Math.round(root.brightness * 100) + "%"
                           color: Colors.colOnSurfaceVariant; font.pixelSize: 11
                           anchors.verticalCenter: parent.verticalCenter }
                }
            }

            HR {}
            SLabel { text: "NIGHT MODE" }

            Item {
                width: parent.width; height: 36
                Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                       text: "Night Mode (4000K)"; color: Colors.colOnSurface; font.pixelSize: 12 }
                Item {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    implicitWidth: nightTog.implicitWidth; implicitHeight: nightTog.implicitHeight
                    Toggle {
                        id: nightTog
                        checked: root.nightMode
                        onToggled: (v) => {
                            root.nightMode = v
                            if (v) gammastepOnProc.running = true
                            else   gammastepOffProc.running = true
                        }
                    }
                }
            }

            Item { height: 8 }
        }
    }
}
