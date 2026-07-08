pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../config"

// Volume via wpctl (reliable), brightness via brightnessctl.
// Scroll anywhere on the volume area to adjust; click the icon to mute.
// Brightness is hidden on desktops with no backlight (max = 0).
Row {
    id: root
    spacing: 10

    // ── Volume state ────────────────────────────────────────────────────
    property real volLevel: 0.0
    property bool volMuted: false

    function parseWpctl(text) {
        const m = text.trim().match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
        if (!m) return
        root.volLevel = parseFloat(m[1])
        root.volMuted = !!m[2]
    }

    // ── Volume ─────────────────────────────────────────────────────────
    Row {
        id: volRow
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter

        // Nerd Font (Font Awesome) glyphs via JS \uXXXX escapes
        //  \uF026 = volume-off   \uF027 = volume-down   \uF028 = volume-up
        Text {
            id: volIcon
            anchors.verticalCenter: parent.verticalCenter
            color: root.volMuted ? Colors.outline : Colors.colOnSurfaceVariant
            font.pixelSize: 13
            font.family: "Symbols Nerd Font Mono"
            text: root.volMuted ? "\uF026"
                : root.volLevel > 0.5 ? "\uF028"
                : "\uF027"

            // Click icon to mute/unmute
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: muteProc.running = true
            }
        }

        Text {
            id: volText
            anchors.verticalCenter: parent.verticalCenter
            color: Colors.colOnSurface
            font.pixelSize: 11
            text: root.volMuted ? "muted" : Math.round(root.volLevel * 100) + "%"
        }

        // Scroll to adjust
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                const step = event.angleDelta.y > 0 ? "+5%" : "-5%"
                setVolProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", step]
                setVolProc.running = true
            }
        }
    }

    // ── Brightness ──────────────────────────────────────────────────────
    Row {
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        visible: brightProc.maxVal > 0

        // \uF185 = fa-sun-o
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Colors.colOnSurfaceVariant
            font.pixelSize: 13
            font.family: "Symbols Nerd Font Mono"
            text: "\uF185"
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Colors.colOnSurface
            font.pixelSize: 11
            text: brightProc.maxVal > 0
                  ? Math.round(brightProc.curVal / brightProc.maxVal * 100) + "%"
                  : "–"
        }
    }

    // ── Processes ───────────────────────────────────────────────────────

    // Read volume via wpctl
    Process {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: root.parseWpctl(text)
        }
    }

    // Toggle mute
    Process {
        id: muteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        onExited: volProc.running = true   // refresh after toggle
    }

    // Set volume (command set dynamically by WheelHandler)
    Process {
        id: setVolProc
        onExited: volProc.running = true   // refresh after change
    }

    // Brightness read
    Process {
        id: brightProc
        property real curVal: 0
        property real maxVal: 0
        command: ["sh", "-c", "brightnessctl g; brightnessctl m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                if (lines.length >= 2) {
                    brightProc.curVal = parseFloat(lines[0]) || 0
                    brightProc.maxVal = parseFloat(lines[1]) || 0
                }
            }
        }
    }

    // Poll volume every 3 s, brightness every 5 s
    Timer {
        interval: 3000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: volProc.running = true
    }
    Timer {
        interval: 5000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: brightProc.running = true
    }
}
