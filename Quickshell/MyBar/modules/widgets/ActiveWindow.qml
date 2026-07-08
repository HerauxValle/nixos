pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../config"

Item {
    id: root
    implicitWidth: Math.min(lbl.implicitWidth + 4, 360)
    implicitHeight: 22
    clip: true
    visible: title.length > 0

    property string title: ""

    // Try QML Hyprland binding first
    readonly property var focusedWin: Hyprland.focusedMonitor?.activeWorkspace?.lastIpcObject
    readonly property string qmlTitle: {
        const w = focusedWin
        if (!w) return ""
        return w["title"] || w["class"] || ""
    }

    // Fall back to hyprctl process poll (more reliable)
    Process {
        id: titleProc
        command: ["bash", "-c", "hyprctl -j activewindow 2>/dev/null | grep -oP '\"title\"\\s*:\\s*\"\\K[^\"]*' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: root.title = text.trim()
        }
    }

    Timer {
        interval: 800; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            // Prefer QML binding, fall back to process
            const qt = root.qmlTitle
            if (qt) root.title = qt
            else if (!titleProc.running) titleProc.running = true
        }
    }

    Text {
        id: lbl
        anchors.centerIn: parent
        text: root.title
        color: Colors.colOnSurface
        font.pixelSize: BarConfig.barFontSize
        opacity: 0.65
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 360)
    }
}
