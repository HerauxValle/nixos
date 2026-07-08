pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import "../../config"
import "../../services"

Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dashWin
            required property ShellScreen modelData
            screen: modelData

            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:mybar-dashboard"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors.top:    true
            anchors.bottom: true
            anchors.left:   true
            anchors.right:  true
            exclusiveZone: 0

            visible: ShellState.dashboardOpen

            // ── MPRIS helper ──────────────────────────────────────────────────────
            readonly property MprisPlayer activePlayer: {
                const vals = Mpris.players.values
                return vals.find(p => p.isPlaying) ??
                       vals.find(p => p.playbackState === MprisPlaybackState.Paused) ?? null
            }

            // ── Weather fetch ─────────────────────────────────────────────────────
            property string weatherRaw:  ""
            property string weatherCond: ""
            property string weatherTemp: ""
            property string weatherLoc:  ""

            Process {
                id: weatherProc
                command: ["bash", "-c", "curl -s \"wttr.in/?format=%C|%t|%l\" --max-time 5 2>/dev/null"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const parts = text.trim().split("|")
                        if (parts.length >= 2) {
                            dashWin.weatherCond = parts[0] ? parts[0].trim() : ""
                            dashWin.weatherTemp = parts[1] ? parts[1].trim() : ""
                            dashWin.weatherLoc  = parts[2] ? parts[2].trim() : ""
                        }
                    }
                }
            }

            Timer {
                interval: 600000; repeat: true; running: ShellState.dashboardOpen
                triggeredOnStart: true
                onTriggered: if (!weatherProc.running) weatherProc.running = true
            }

            // ── CPU stat ─────────────────────────────────────────────────────────
            property real cpuPercent: 0
            property var  _cpuPrev: null

            Process {
                id: cpuProc
                command: ["bash", "-c", "cat /proc/stat | head -1"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const parts = text.trim().split(/\s+/)
                        const vals  = parts.slice(1).map(Number)
                        const idle  = vals[3] + vals[4]
                        const total = vals.reduce((a,b) => a+b, 0)
                        if (dashWin._cpuPrev) {
                            const dIdle  = idle  - dashWin._cpuPrev.idle
                            const dTotal = total - dashWin._cpuPrev.total
                            if (dTotal > 0)
                                dashWin.cpuPercent = Math.round((1 - dIdle/dTotal) * 100)
                        }
                        dashWin._cpuPrev = { idle: idle, total: total }
                    }
                }
            }

            // ── RAM stat ─────────────────────────────────────────────────────────
            property real ramUsedGb:  0
            property real ramTotalGb: 0

            Process {
                id: ramProc
                command: ["bash", "-c", "grep -E '^(MemTotal|MemAvailable):' /proc/meminfo"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const lines = text.trim().split("\n")
                        let total = 0, avail = 0
                        for (const l of lines) {
                            const m = l.match(/(MemTotal|MemAvailable):\s+(\d+)/)
                            if (!m) continue
                            if (m[1] === "MemTotal")     total = parseInt(m[2])
                            if (m[1] === "MemAvailable") avail = parseInt(m[2])
                        }
                        if (total > 0) {
                            dashWin.ramTotalGb = (total / 1048576).toFixed(1)
                            dashWin.ramUsedGb  = ((total - avail) / 1048576).toFixed(1)
                        }
                    }
                }
            }

            // ── Storage stat ─────────────────────────────────────────────────────
            property string storageUsed:  ""
            property string storageTotal: ""

            Process {
                id: dfProc
                command: ["bash", "-c", "df -h / | tail -1"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const parts = text.trim().split(/\s+/)
                        if (parts.length >= 3) {
                            dashWin.storageUsed  = parts[2]
                            dashWin.storageTotal = parts[1]
                        }
                    }
                }
            }

            // ── Network stat ─────────────────────────────────────────────────────
            property real netRxMb: 0
            property real netTxMb: 0
            property var  _netPrev: null

            Process {
                id: netProc
                command: ["bash", "-c", "cat /proc/net/dev | grep -v 'lo:' | awk 'NR>2 {rx+=$2; tx+=$10} END{print rx, tx}'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const parts = text.trim().split(" ")
                        if (parts.length >= 2) {
                            const rx = parseInt(parts[0])
                            const tx = parseInt(parts[1])
                            if (dashWin._netPrev) {
                                dashWin.netRxMb = ((rx - dashWin._netPrev.rx) / 1048576).toFixed(2)
                                dashWin.netTxMb = ((tx - dashWin._netPrev.tx) / 1048576).toFixed(2)
                            }
                            dashWin._netPrev = { rx: rx, tx: tx }
                        }
                    }
                }
            }

            // Poll stats
            Timer {
                interval: 2000; repeat: true; running: ShellState.dashboardOpen
                triggeredOnStart: true
                onTriggered: {
                    if (!cpuProc.running) cpuProc.running = true
                    if (!ramProc.running) ramProc.running = true
                    if (!dfProc.running)  dfProc.running  = true
                    if (!netProc.running) netProc.running = true
                }
            }



            // ── Backdrop: click outside to close ─────────────────────────────────
            MouseArea {
                anchors.fill: parent
                z: 0
                onClicked: ShellState.closeDashboard()
            }

            // ── Dashboard panel ───────────────────────────────────────────────────
            Rectangle {
                id: panel
                z: 1

                readonly property int panelW: Math.min(900, Math.round(dashWin.screen.width  * 0.65))
                readonly property int panelH: Math.min(580, Math.round(dashWin.screen.height * 0.58))

                width:  panelW
                height: panelH
                x: (dashWin.screen.width  - panelW) / 2
                y: (dashWin.screen.height - panelH) / 2

                radius: 20
                color:  Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, 0.92)
                border.color: Colors.popupBorder
                border.width: 1

                // Absorb clicks so backdrop doesn't fire inside panel
                MouseArea { anchors.fill: parent; onClicked: {} }

                // ── Animate in ────────────────────────────────────────────────────
                opacity: ShellState.dashboardOpen ? 1 : 0
                scale:   ShellState.dashboardOpen ? 1 : 0.95
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                // ── Header ────────────────────────────────────────────────────────
                Item {
                    id: dashHdr
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 20 }
                    height: 38

                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "Dashboard"
                        color: Colors.colOnSurface; font.pixelSize: 16; font.weight: Font.Medium
                    }
                    Text {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: "\u2715"
                        color: Colors.colOnSurfaceVariant; font.pixelSize: 14
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.closeDashboard()
                        }
                    }
                }

                Rectangle {
                    id: dashDivTop
                    anchors { top: dashHdr.bottom; left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 20 }
                    height: 1; color: Colors.popupBorder; opacity: 0.6
                }

                // ── Content area ─────────────────────────────────────────────────
                Item {
                    id: dashBody
                    anchors {
                        top:    dashDivTop.bottom
                        left:   parent.left
                        right:  parent.right
                        bottom: parent.bottom
                        margins: 16
                    }

                    // ── Row 1: Weather + Now Playing ─────────────────────────────
                    Row {
                        id: row1
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        spacing: 12

                        // Weather card
                        Rectangle {
                            width:  (parent.width - 12) / 2
                            height: 130
                            radius: 14
                            color:  Colors.surfaceContainer
                            border.color: Colors.popupBorder; border.width: 1

                            Column {
                                anchors { fill: parent; margins: 14 }
                                spacing: 6

                                Text {
                                    text: "WEATHER"
                                    color: Colors.primary; font.pixelSize: 8
                                    font.weight: Font.Medium; font.letterSpacing: 1
                                    opacity: 0.75
                                }
                                Text {
                                    text: dashWin.weatherTemp || "--"
                                    color: Colors.colOnSurface
                                    font.pixelSize: 32; font.weight: Font.Light
                                }
                                Text {
                                    text: dashWin.weatherCond || "Loading..."
                                    color: Colors.colOnSurfaceVariant; font.pixelSize: 11
                                    elide: Text.ElideRight; width: parent.width
                                }
                                Text {
                                    visible: dashWin.weatherLoc !== ""
                                    text: dashWin.weatherLoc
                                    color: Colors.colOnSurfaceVariant; font.pixelSize: 9
                                    opacity: 0.7; elide: Text.ElideRight; width: parent.width
                                }
                            }
                        }

                        // Now Playing card
                        Rectangle {
                            width:  (parent.width - 12) / 2
                            height: 130
                            radius: 14
                            color:  Colors.surfaceContainer
                            border.color: Colors.popupBorder; border.width: 1

                            Item {
                                anchors { fill: parent; margins: 14 }

                                Text {
                                    id: npLabel
                                    anchors { top: parent.top; left: parent.left }
                                    text: "NOW PLAYING"
                                    color: Colors.primary; font.pixelSize: 8
                                    font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.75
                                }

                                // No media state
                                Text {
                                    visible: dashWin.activePlayer === null
                                    anchors.centerIn: parent
                                    text: "No media playing"
                                    color: Colors.colOnSurfaceVariant; font.pixelSize: 11; opacity: 0.6
                                }

                                // Media info
                                Column {
                                    visible: dashWin.activePlayer !== null
                                    anchors { top: npLabel.bottom; left: parent.left; right: parent.right; topMargin: 6; bottom: parent.bottom }
                                    spacing: 4

                                    Text {
                                        text: dashWin.activePlayer?.trackTitle || ""
                                        color: Colors.colOnSurface; font.pixelSize: 12; font.weight: Font.Medium
                                        elide: Text.ElideRight; width: parent.width
                                    }
                                    Text {
                                        text: dashWin.activePlayer?.trackArtist || ""
                                        color: Colors.colOnSurfaceVariant; font.pixelSize: 10
                                        elide: Text.ElideRight; width: parent.width
                                    }

                                    // Progress bar (static, position unavailable via basic MPRIS)
                                    Rectangle {
                                        width: parent.width; height: 4; radius: 2
                                        color: Colors.surfaceContainerHigh
                                        Rectangle {
                                            width: parent.parent.width * 0.4
                                            height: parent.height; radius: parent.radius
                                            color: Colors.primary
                                        }
                                    }

                                    // Transport controls
                                    Row {
                                        spacing: 8
                                        // \uF048 = prev
                                        Text {
                                            font.pixelSize: 14; font.family: "Symbols Nerd Font Mono"
                                            color: Colors.colOnSurfaceVariant; text: "\uF048"
                                            opacity: dashWin.activePlayer?.canGoPrevious ?? false ? 1 : 0.3
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dashWin.activePlayer?.previous() }
                                        }
                                        Rectangle {
                                            width: 28; height: 20; radius: 10; color: Colors.primary
                                            Text {
                                                anchors.centerIn: parent
                                                font.pixelSize: 10; font.family: "Symbols Nerd Font Mono"
                                                color: Colors.colOnPrimary
                                                text: dashWin.activePlayer?.isPlaying ? "\uF04C" : "\uF04B"
                                            }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dashWin.activePlayer?.togglePlaying() }
                                        }
                                        // \uF051 = next
                                        Text {
                                            font.pixelSize: 14; font.family: "Symbols Nerd Font Mono"
                                            color: Colors.colOnSurfaceVariant; text: "\uF051"
                                            opacity: dashWin.activePlayer?.canGoNext ?? false ? 1 : 0.3
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dashWin.activePlayer?.next() }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Row 2: Workspaces ─────────────────────────────────────────
                    Item {
                        id: row2
                        anchors { top: row1.bottom; left: parent.left; right: parent.right; topMargin: 12 }
                        height: 70

                        Text {
                            id: wsLabel
                            text: "WORKSPACES"
                            color: Colors.primary; font.pixelSize: 8
                            font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.75
                        }

                        Row {
                            anchors { top: wsLabel.bottom; left: parent.left; right: parent.right; topMargin: 6 }
                            spacing: 8

                            Repeater {
                                model: 5
                                Rectangle {
                                    required property int index
                                    readonly property int wsId: index + 1
                                    readonly property bool isActive: {
                                        const ws = Hyprland.focusedMonitor?.activeWorkspace
                                        return ws ? ws.id === wsId : wsId === 1
                                    }

                                    width:  (row2.width - 32) / 5
                                    height: 44
                                    radius: 10
                                    color: isActive
                                           ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18)
                                           : Colors.surfaceContainerHigh
                                    border.color: isActive ? Colors.primary : Colors.popupBorder
                                    border.width: isActive ? 2 : 1

                                    Behavior on color       { ColorAnimation { duration: 120 } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "0" + parent.wsId
                                        font.pixelSize: 14; font.weight: Font.Medium
                                        color: parent.isActive ? Colors.primary : Colors.colOnSurfaceVariant
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: Hyprland.dispatch("workspace " + parent.wsId)
                                    }
                                }
                            }
                        }
                    }

                    // ── Row 3: Stat cards ─────────────────────────────────────────
                    Row {
                        id: row3
                        anchors { top: row2.bottom; left: parent.left; right: parent.right; topMargin: 12 }
                        height: 100
                        spacing: 10

                        // Reusable stat card
                        component StatCard: Rectangle {
                            required property string cardLabel
                            required property string mainVal
                            required property string subVal
                            required property real   fillRatio

                            radius: 14
                            color:  Colors.surfaceContainer
                            border.color: Colors.popupBorder; border.width: 1

                            Column {
                                anchors { fill: parent; margins: 12 }
                                spacing: 6

                                Text {
                                    text: cardLabel
                                    color: Colors.primary; font.pixelSize: 8
                                    font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.75
                                }
                                Text {
                                    text: mainVal
                                    color: Colors.colOnSurface; font.pixelSize: 22; font.weight: Font.Light
                                }
                                Text {
                                    text: subVal
                                    color: Colors.colOnSurfaceVariant; font.pixelSize: 9
                                    elide: Text.ElideRight; width: parent.width
                                }
                                // Mini progress bar
                                Rectangle {
                                    width: parent.width; height: 4; radius: 2
                                    color: Colors.surfaceContainerHigh
                                    Rectangle {
                                        width: Math.max(0, Math.min(1, fillRatio)) * parent.width
                                        height: parent.height; radius: parent.radius
                                        color: fillRatio > 0.85 ? Colors.error : Colors.primary
                                        Behavior on width { NumberAnimation { duration: 300 } }
                                    }
                                }
                            }
                        }

                        StatCard {
                            width: (parent.width - 30) / 4; height: parent.height
                            cardLabel: "CPU"
                            mainVal: dashWin.cpuPercent + "%"
                            subVal:  "processor"
                            fillRatio: dashWin.cpuPercent / 100
                        }
                        StatCard {
                            width: (parent.width - 30) / 4; height: parent.height
                            cardLabel: "RAM"
                            mainVal: dashWin.ramUsedGb + " GB"
                            subVal:  "of " + dashWin.ramTotalGb + " GB"
                            fillRatio: dashWin.ramTotalGb > 0 ? dashWin.ramUsedGb / dashWin.ramTotalGb : 0
                        }
                        StatCard {
                            width: (parent.width - 30) / 4; height: parent.height
                            cardLabel: "NETWORK"
                            mainVal: dashWin.netRxMb + " MB"
                            subVal:  "\u2193 rx  \u2191 " + dashWin.netTxMb + " MB tx"
                            fillRatio: Math.min(parseFloat(dashWin.netRxMb) / 10, 1)
                        }
                        StatCard {
                            width: (parent.width - 30) / 4; height: parent.height
                            cardLabel: "STORAGE"
                            mainVal: dashWin.storageUsed || "--"
                            subVal:  "of " + (dashWin.storageTotal || "--")
                            fillRatio: {
                                if (!dashWin.storageUsed || !dashWin.storageTotal) return 0
                                const used  = parseFloat(dashWin.storageUsed)
                                const total = parseFloat(dashWin.storageTotal)
                                return total > 0 ? used / total : 0
                            }
                        }
                    }
                }
            }
        }
    }
}
