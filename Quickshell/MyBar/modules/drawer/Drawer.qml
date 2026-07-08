pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import "../../config"
import "../../services"

// Add to hyprland.conf: bind = SUPER, B, exec, qs-ipc toggle-drawer

PanelWindow {
    id: drawerWin
    color: "transparent"

    WlrLayershell.namespace: "quickshell:mybar-drawer"
    WlrLayershell.layer:     WlrLayer.Overlay
    property bool _taskInputActive: false
    WlrLayershell.keyboardFocus: drawerWin._taskInputActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors { left: true; top: true; bottom: true; right: true }
    exclusiveZone: 0

    implicitWidth: drawerWin.screen ? drawerWin.screen.width : 1920

    visible: ShellState.drawerOpen || drawerPanel.drawerVisible

    // Restrict input to the drawer panel only — lets other windows (bar popup) receive clicks
    mask: Region { item: drawerPanel }

    // ── MPRIS helper ─────────────────────────────────────────────────────
    readonly property MprisPlayer activePlayer: {
        const vals = Mpris.players.values
        return vals.find(p => p.isPlaying) ??
               vals.find(p => p.playbackState === MprisPlaybackState.Paused) ?? null
    }

    // ── Drawer panel ──────────────────────────────────────────────────────
    Rectangle {
        id: drawerPanel
        width: Math.round(drawerPanel.screenW * 0.167)

        color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)
        border.width: 1
        border.color: Colors.popupBorder
        clip: true

        readonly property real _r: 14
        readonly property bool _pill: BarConfig.fillMode === "pill"
        // pill: all round; hanging: square on screen side, round on open side
        topLeftRadius:     _pill ? _r : (fromRight ? _r : 0)
        topRightRadius:    _pill ? _r : (fromRight ? 0 : _r)
        bottomLeftRadius:  _pill ? _r : (fromRight ? _r : 0)
        bottomRightRadius: _pill ? _r : (fromRight ? 0 : _r)

        readonly property bool fromRight:  BarConfig.barPosition === "right"
        readonly property int  screenW:    drawerWin.screen ? drawerWin.screen.width : 1920
        readonly property int  screenH:    drawerWin.screen ? drawerWin.screen.height : 1080

        // Vertical positioning: full=flush to bar edge, pill/hanging=add 8px margin
        readonly property int  _barEdgeTop:    BarConfig.barPosition === "top"    ? BarConfig.barMargin + BarConfig.barHeight : 0
        readonly property int  _barEdgeBottom: BarConfig.barPosition === "bottom" ? BarConfig.barMargin + BarConfig.barHeight : 0
        readonly property bool _full: false  // full mode removed
        readonly property int  _maxH: _full
            ? (screenH - _barEdgeTop - _barEdgeBottom)
            : Math.min(screenH - _barEdgeTop - _barEdgeBottom - 24, Math.round(screenH * 0.5))
        readonly property bool drawerVisible: fromRight
            ? drawerPanel.x < screenW
            : drawerPanel.x > -width

        y: _full
           ? _barEdgeTop
           : Math.max(_barEdgeTop + 8, Math.round((screenH - _maxH) / 2))
        height: _maxH

        readonly property int _hMargin: BarConfig.fillMode === "pill" ? BarConfig.barMargin : 0
        x: {
            if (fromRight)
                return ShellState.drawerOpen ? (screenW - width - _hMargin) : screenW
            else
                return ShellState.drawerOpen ? _hMargin : -width
        }
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; onClicked: {} }

        // ── Tab bar ───────────────────────────────────────────────────────
        Item {
            id: tabBar
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: BarConfig.sp(44)

            property int _slideDir: 0

            Row {
                anchors { left: parent.left; leftMargin: BarConfig.sp(12); verticalCenter: parent.verticalCenter }
                spacing: BarConfig.sp(4)

                Repeater {
                    model: ["Essentials", "Dashboard", "Notifications"]
                    Rectangle {
                        required property string modelData
                        required property int    index
                        readonly property bool   active: ShellState.drawerTab === index
                        height: BarConfig.sp(28)
                        width: tabLabel.implicitWidth + 20
                        radius: BarConfig.sp(6)
                        color: active ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.15)
                                      : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: BarConfig.fsMd
                            font.weight: active ? Font.Medium : Font.Normal
                            color: active ? Colors.primary : Colors.colOnSurfaceVariant
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                tabBar._slideDir = index > ShellState.drawerTab ? 1 : -1
                                ShellState.drawerTab = index
                            }
                        }
                    }
                }
            }

            Text {
                anchors { right: parent.right; rightMargin: BarConfig.sp(14); verticalCenter: parent.verticalCenter }
                text: "✕"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsLg
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.closeDrawer() }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Colors.popupBorder; opacity: 0.6 }
        }

        // ── Tab content ───────────────────────────────────────────────────
        Item {
            id: tabContent
            anchors { top: tabBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }

            property real _slideX: 0
            transform: Translate { x: tabContent._slideX }

            SequentialAnimation {
                id: tabSlideAnim
                PropertyAction  { target: tabContent; property: "_slideX"; value: tabBar._slideDir * tabContent.width * 0.06 }
                NumberAnimation { target: tabContent; property: "_slideX"; to: 0; duration: 200; easing.type: Easing.OutCubic }
            }

            Connections {
                target: ShellState
                function onDrawerTabChanged() { if (tabBar._slideDir !== 0) tabSlideAnim.restart() }
            }

            // ═══════════════════════════════════════════════════════════════
            // Tab 0: ESSENTIALS
            // ═══════════════════════════════════════════════════════════════
            Item {
                anchors.fill: parent
                visible: ShellState.drawerTab === 0

                // ── Weather data ──────────────────────────────────────────────────
                property string weatherTemp:  "--"
                property string weatherCond:  "Loading..."
                property string weatherLoc:   ""
                property string weatherIcon:  ""

                id: essTab

                function parseWeather(raw) {
                    raw = (raw || "").trim()
                    if (raw.length < 3) {
                        essTab.weatherTemp = "N/A"; essTab.weatherCond = "Unavailable"; essTab.weatherLoc = ""; return
                    }
                    const tempMatch = raw.match(/([-+]?\d+)\s*°[CF]/)
                    if (!tempMatch) { essTab.weatherTemp = "?"; essTab.weatherCond = raw; return }
                    const temp = tempMatch[0]
                    const tempIdx = raw.indexOf(temp)
                    const cond = tempIdx > 0 ? raw.substring(0, tempIdx).trim() : "Unknown"
                    const loc  = raw.substring(tempIdx + temp.length).trim()
                    essTab.weatherTemp = temp; essTab.weatherCond = cond; essTab.weatherLoc = loc
                    const c = cond.toLowerCase()
                    if      (c.includes("thunder") || c.includes("storm"))    essTab.weatherIcon = ""
                    else if (c.includes("snow")    || c.includes("blizzard")) essTab.weatherIcon = ""
                    else if (c.includes("rain")    || c.includes("drizzle"))  essTab.weatherIcon = ""
                    else if (c.includes("fog")     || c.includes("mist"))     essTab.weatherIcon = ""
                    else if (c.includes("overcast"))                          essTab.weatherIcon = ""
                    else if (c.includes("cloud"))                             essTab.weatherIcon = ""
                    else if (c.includes("clear")   || c.includes("sunny"))   essTab.weatherIcon = ""
                    else                                                       essTab.weatherIcon = ""
                }

                Process {
                    id: weatherProc
                    command: ["bash", "-c", "curl -s 'wttr.in/?format=%C+%t+%l' --max-time 5 2>/dev/null || echo 'N/A'"]
                    stdout: StdioCollector { onStreamFinished: essTab.parseWeather(text) }
                }
                Timer { interval: 600000; repeat: true; running: true; triggeredOnStart: true
                        onTriggered: if (!weatherProc.running) weatherProc.running = true }

                // ── System stats ──────────────────────────────────────────────────
                property real cpuPercent:   0.0
                property var  _cpuPrev:     null
                property real ramUsedGb:    0.0
                property real ramTotalGb:   0.0
                property real ramPercent:   0.0
                property real netMbps:      0.0
                property var  _netPrev:     null

                Process {
                    id: cpuProc
                    command: ["bash", "-c", "head -1 /proc/stat"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const parts = text.trim().split(/\s+/)
                            if (parts.length < 5) return
                            const vals  = parts.slice(1).map(Number)
                            const idle  = vals[3] + (vals[4] || 0)
                            const total = vals.reduce((a, b) => a + b, 0)
                            if (essTab._cpuPrev) {
                                const dI = idle  - essTab._cpuPrev.idle
                                const dT = total - essTab._cpuPrev.total
                                if (dT > 0) essTab.cpuPercent = Math.max(0, Math.min(100, (1 - dI / dT) * 100))
                            }
                            essTab._cpuPrev = { idle: idle, total: total }
                        }
                    }
                }
                Timer { interval: 2000; repeat: true; running: true; triggeredOnStart: true
                        onTriggered: if (!cpuProc.running) cpuProc.running = true }

                Process {
                    id: ramProc
                    command: ["bash", "-c", "grep -E '^(MemTotal|MemAvailable):' /proc/meminfo"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const lines = text.trim().split("\n")
                            let total = 0, avail = 0
                            for (const l of lines) {
                                const m = l.match(/^(\w+):\s+(\d+)/)
                                if (!m) continue
                                if (m[1] === "MemTotal")     total = parseInt(m[2])
                                if (m[1] === "MemAvailable") avail = parseInt(m[2])
                            }
                            if (total > 0) {
                                essTab.ramTotalGb = total / 1048576
                                essTab.ramUsedGb  = (total - avail) / 1048576
                                essTab.ramPercent = (total - avail) / total * 100
                            }
                        }
                    }
                }
                Timer { interval: 3000; repeat: true; running: true; triggeredOnStart: true
                        onTriggered: if (!ramProc.running) ramProc.running = true }

                Process {
                    id: netProc
                    command: ["bash", "-c", "grep -v -E '^(Inter|\\s+face|\\s*lo:)' /proc/net/dev | awk '{rx+=$2; tx+=$10} END{print rx+0, tx+0}'"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const parts = text.trim().split(" ")
                            if (parts.length < 2) return
                            const rx = parseInt(parts[0]) || 0
                            const tx = parseInt(parts[1]) || 0
                            const now = Date.now()
                            if (essTab._netPrev) {
                                const dt = (now - essTab._netPrev.ts) / 1000.0
                                if (dt > 0) {
                                    const dB = (rx - essTab._netPrev.rx) + (tx - essTab._netPrev.tx)
                                    essTab.netMbps = Math.max(0, dB / dt / 1048576)
                                }
                            }
                            essTab._netPrev = { rx: rx, tx: tx, ts: now }
                        }
                    }
                }
                Timer { interval: 2000; repeat: true; running: true; triggeredOnStart: true
                        onTriggered: if (!netProc.running) netProc.running = true }

                property int calYear:  new Date().getFullYear()
                property int calMonth: new Date().getMonth()
                property bool addingTask:  false
                onAddingTaskChanged: {
                    drawerWin._taskInputActive = addingTask
                    if (addingTask) Qt.callLater(() => newTaskInput.forceActiveFocus())
                }

                Flickable {
                    id: essFlick
                    anchors.fill: parent
                    contentWidth:  width
                    contentHeight: essCol.implicitHeight + 24
                    clip: true

                    Column {
                        id: essCol
                        width: parent.width - 24
                        x: 12; y: 12
                        spacing: BarConfig.sp(12)

                        // ── Weather card ──────────────────────────────────────────
                        Rectangle {
                            width: parent.width; height: BarConfig.sp(100); radius: BarConfig.sp(12)
                            color: Colors.surfaceContainerHigh
                            border.color: Colors.popupBorder; border.width: 1
                            Item {
                                anchors { fill: parent; margins: BarConfig.sp(14) }
                                Text {
                                    id: wIcon
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    text: essTab.weatherIcon; font.family: "Symbols Nerd Font Mono"
                                    font.pixelSize: Math.round(36 * BarConfig.uiScale); color: Colors.primary
                                }
                                Column {
                                    anchors.left: wIcon.right; anchors.leftMargin: BarConfig.sp(14)
                                    anchors.verticalCenter: parent.verticalCenter; spacing: BarConfig.sp(4)
                                    Text { text: essTab.weatherTemp; color: Colors.colOnSurface; font.pixelSize: Math.round(28 * BarConfig.uiScale); font.weight: Font.Bold }
                                    Text { text: essTab.weatherCond; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd }
                                    Text { text: essTab.weatherLoc;  color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm; opacity: 0.7 }
                                }
                            }
                        }

                        // ── Calendar card ─────────────────────────────────────────
                        Rectangle {
                            width: parent.width; radius: BarConfig.sp(12)
                            color: Colors.surfaceContainerHigh
                            border.color: Colors.popupBorder; border.width: 1
                            implicitHeight: calCol.implicitHeight + 20
                            Column {
                                id: calCol
                                width: parent.width - 20; x: 10; y: 10; spacing: BarConfig.sp(8)
                                Item {
                                    width: parent.width; height: BarConfig.sp(28)
                                    Text {
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                        text: {
                                            const months = ["January","February","March","April","May","June",
                                                            "July","August","September","October","November","December"]
                                            return months[essTab.calMonth] + " " + essTab.calYear
                                        }
                                        color: Colors.colOnSurface; font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                                    }
                                    Item {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: BarConfig.sp(56); height: BarConfig.sp(28)
                                        Rectangle {
                                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                            width: BarConfig.sp(24); height: BarConfig.sp(24); radius: BarConfig.sp(6)
                                            color: prevHov.containsMouse ? Colors.surfaceContainer : "transparent"
                                            Text { anchors.centerIn: parent; text: "‹"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsLg }
                                            HoverHandler { id: prevHov }
                                            MouseArea {
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: { if (essTab.calMonth === 0) { essTab.calMonth = 11; essTab.calYear-- } else { essTab.calMonth-- } }
                                            }
                                        }
                                        Rectangle {
                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                            width: BarConfig.sp(24); height: BarConfig.sp(24); radius: BarConfig.sp(6)
                                            color: nextHov.containsMouse ? Colors.surfaceContainer : "transparent"
                                            Text { anchors.centerIn: parent; text: "›"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsLg }
                                            HoverHandler { id: nextHov }
                                            MouseArea {
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: { if (essTab.calMonth === 11) { essTab.calMonth = 0; essTab.calYear++ } else { essTab.calMonth++ } }
                                            }
                                        }
                                    }
                                }
                                Row {
                                    width: parent.width
                                    Repeater {
                                        model: ["Mo","Tu","We","Th","Fr","Sa","Su"]
                                        Text {
                                            required property string modelData
                                            width: calCol.width / 7; text: modelData
                                            color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm
                                            horizontalAlignment: Text.AlignHCenter; opacity: 0.7
                                        }
                                    }
                                }
                                Grid {
                                    id: calGrid
                                    width: parent.width; columns: 7
                                    property int todayDay:   new Date().getDate()
                                    property int todayMonth: new Date().getMonth()
                                    property int todayYear:  new Date().getFullYear()
                                    property int firstWeekday: { const d = new Date(essTab.calYear, essTab.calMonth, 1); return (d.getDay() + 6) % 7 }
                                    property int daysInMonth: new Date(essTab.calYear, essTab.calMonth + 1, 0).getDate()
                                    property int totalCells: firstWeekday + daysInMonth
                                    Repeater {
                                        model: { const t = calGrid.totalCells; const rem = t % 7; return t + (rem === 0 ? 0 : 7 - rem) }
                                        delegate: Item {
                                            required property int index
                                            width: calGrid.width / 7; height: BarConfig.sp(26)
                                            readonly property int  dayNum:     index - calGrid.firstWeekday + 1
                                            readonly property bool isValidDay: dayNum >= 1 && dayNum <= calGrid.daysInMonth
                                            readonly property bool isToday: isValidDay && dayNum === calGrid.todayDay && essTab.calMonth === calGrid.todayMonth && essTab.calYear === calGrid.todayYear
                                            Rectangle {
                                                width: BarConfig.sp(22); height: BarConfig.sp(22); radius: BarConfig.sp(11); anchors.centerIn: parent
                                                color: isToday ? Colors.primary : "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: isValidDay ? dayNum : ""
                                                    color: isToday ? Colors.colOnPrimary : Colors.colOnSurface
                                                    font.pixelSize: BarConfig.fsMd; font.weight: isToday ? Font.Bold : Font.Normal
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── Tasks card ────────────────────────────────────────────
                        Rectangle {
                            width: parent.width; radius: BarConfig.sp(12)
                            color: Colors.surfaceContainerHigh
                            border.color: Colors.popupBorder; border.width: 1
                            implicitHeight: tasksCol.implicitHeight + 20
                            Column {
                                id: tasksCol
                                width: parent.width - 20; x: 10; y: 10; spacing: BarConfig.sp(8)
                                Text { text: "TASKS"; color: Colors.primary; font.pixelSize: BarConfig.fsSm; font.weight: Font.Bold; font.letterSpacing: 1.5 }
                                Repeater {
                                    model: BarConfig.tasks
                                    Item {
                                        required property string modelData
                                        required property int    index
                                        width: tasksCol.width; height: BarConfig.sp(28)
                                        Text {
                                            anchors.left: parent.left; anchors.leftMargin: BarConfig.sp(4)
                                            anchors.right: removeBtn.left; anchors.rightMargin: BarConfig.sp(8)
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "● " + modelData; color: Colors.colOnSurface; font.pixelSize: BarConfig.fs; elide: Text.ElideRight
                                        }
                                        Text {
                                            id: removeBtn
                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                            text: "✕"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm; opacity: 0.5
                                            MouseArea {
                                                anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                                                onClicked: BarConfig.removeTask(index)
                                            }
                                        }
                                    }
                                }
                                Item {
                                    width: parent.width; height: BarConfig.sp(32)
                                    Rectangle {
                                        visible: essTab.addingTask; anchors.fill: parent
                                        color: Colors.surfaceContainer; radius: BarConfig.sp(6)
                                        border.color: Colors.primary; border.width: 1
                                        TextInput {
                                            id: newTaskInput
                                            anchors { left: parent.left; right: cancelBtn.left; verticalCenter: parent.verticalCenter; leftMargin: BarConfig.sp(8); rightMargin: BarConfig.sp(4) }
                                            color: Colors.colOnSurface; font.pixelSize: BarConfig.fs; focus: essTab.addingTask
                                            Keys.onReturnPressed: {
                                                if (newTaskInput.text.trim().length > 0)
                                                    BarConfig.addTask(newTaskInput.text.trim())
                                                essTab.addingTask = false; newTaskInput.text = ""
                                            }
                                            Keys.onEscapePressed: { essTab.addingTask = false; newTaskInput.text = "" }
                                        }
                                        Text {
                                            id: cancelBtn
                                            anchors { right: parent.right; rightMargin: BarConfig.sp(8); verticalCenter: parent.verticalCenter }
                                            text: "✕"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm
                                            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                                                onClicked: { essTab.addingTask = false; newTaskInput.text = "" }
                                            }
                                        }
                                    }
                                    Item {
                                        visible: !essTab.addingTask; anchors.fill: parent
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "+ Add Task"; color: Colors.primary; font.pixelSize: BarConfig.fs }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: essTab.addingTask = true }
                                    }
                                }
                            }
                        }

                        // ── System card ───────────────────────────────────────────
                        Rectangle {
                            width: parent.width; radius: BarConfig.sp(12)
                            color: Colors.surfaceContainerHigh
                            border.color: Colors.popupBorder; border.width: 1
                            implicitHeight: sysCol.implicitHeight + 20
                            Column {
                                id: sysCol
                                width: parent.width - 20; x: 10; y: 10; spacing: BarConfig.sp(10)
                                Text { text: "SYSTEM"; color: Colors.primary; font.pixelSize: BarConfig.fsSm; font.weight: Font.Bold; font.letterSpacing: 1.5 }
                                component StatRow: Item {
                                    id: statItem
                                    required property string label
                                    required property string value
                                    required property real   pct
                                    width: parent.width; height: BarConfig.sp(38)
                                    Item {
                                        width: parent.width; height: BarConfig.sp(18)
                                        Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: statItem.label; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd }
                                        Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: statItem.value; color: Colors.colOnSurface; font.pixelSize: BarConfig.fsMd }
                                    }
                                    Rectangle {
                                        anchors.bottom: parent.bottom; width: parent.width; height: BarConfig.sp(5); radius: BarConfig.sp(3); color: Colors.surfaceContainer
                                        Rectangle {
                                            width: parent.width * Math.min(1, Math.max(0, statItem.pct / 100))
                                            height: parent.height; radius: parent.radius; color: Colors.primary
                                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                                StatRow { label: "CPU"; value: Math.round(essTab.cpuPercent) + "%"; pct: essTab.cpuPercent }
                                StatRow { label: "RAM"; value: essTab.ramUsedGb.toFixed(1) + " / " + essTab.ramTotalGb.toFixed(1) + " GB"; pct: essTab.ramPercent }
                                StatRow { label: "NET"; value: essTab.netMbps.toFixed(1) + " MB/s"; pct: Math.min(100, essTab.netMbps) }
                                Item { height: BarConfig.sp(2) }
                            }
                        }

                        Item { height: BarConfig.sp(8) }
                    }
                }
                // Scrollbar
                Rectangle {
                    visible: essFlick.contentHeight > essFlick.height
                    anchors.right: parent.right; anchors.rightMargin: BarConfig.sp(4)
                    readonly property real _r: BarConfig.sp(14)
                    readonly property real _thumbH: essFlick.visibleArea.heightRatio * essFlick.height
                    y: Math.max(essFlick.y + _r, Math.min(essFlick.y + essFlick.height - _thumbH - _r,
                                essFlick.y + essFlick.visibleArea.yPosition * essFlick.height))
                    width: BarConfig.sp(3); height: _thumbH
                    radius: BarConfig.sp(2); color: Colors.outline; opacity: 0.5; z: 5
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // Tab 1: DASHBOARD
            // ═══════════════════════════════════════════════════════════════
            Item {
                anchors.fill: parent
                visible: ShellState.drawerTab === 1

                // Storage stat
                property string storageUsed:  ""
                property string storageTotal: ""
                property real   cpuPct: 0
                property var    _cpuPrev2: null
                property real   ramUsed: 0
                property real   ramTotal: 0

                id: dashTab

                Process {
                    id: dfProc2
                    command: ["bash", "-c", "df -h / | tail -1"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const parts = text.trim().split(/\s+/)
                            if (parts.length >= 3) { dashTab.storageUsed = parts[2]; dashTab.storageTotal = parts[1] }
                        }
                    }
                }
                Process {
                    id: cpuProc2
                    command: ["bash", "-c", "head -1 /proc/stat"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const parts = text.trim().split(/\s+/)
                            if (parts.length < 5) return
                            const vals  = parts.slice(1).map(Number)
                            const idle  = vals[3] + (vals[4] || 0)
                            const total = vals.reduce((a, b) => a + b, 0)
                            if (dashTab._cpuPrev2) {
                                const dI = idle  - dashTab._cpuPrev2.idle
                                const dT = total - dashTab._cpuPrev2.total
                                if (dT > 0) dashTab.cpuPct = Math.round(Math.max(0, Math.min(100, (1 - dI / dT) * 100)))
                            }
                            dashTab._cpuPrev2 = { idle: idle, total: total }
                        }
                    }
                }
                Process {
                    id: ramProc2
                    command: ["bash", "-c", "grep -E '^(MemTotal|MemAvailable):' /proc/meminfo"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const lines = text.trim().split("\n")
                            let total = 0, avail = 0
                            for (const l of lines) {
                                const m = l.match(/^(\w+):\s+(\d+)/)
                                if (!m) continue
                                if (m[1] === "MemTotal")     total = parseInt(m[2])
                                if (m[1] === "MemAvailable") avail = parseInt(m[2])
                            }
                            if (total > 0) { dashTab.ramTotal = total / 1048576; dashTab.ramUsed = (total - avail) / 1048576 }
                        }
                    }
                }
                Timer {
                    interval: 2000; repeat: true; running: ShellState.drawerTab === 1 && ShellState.drawerOpen; triggeredOnStart: true
                    onTriggered: { if (!cpuProc2.running) cpuProc2.running = true; if (!ramProc2.running) ramProc2.running = true; if (!dfProc2.running) dfProc2.running = true }
                }

                Flickable {
                    id: dashFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: dashCol.implicitHeight + 24
                    clip: true

                    Column {
                        id: dashCol
                        width: parent.width - 24; x: 12; y: 12; spacing: BarConfig.sp(12)

                        // ── Now Playing ───────────────────────────────────────────
                        Rectangle {
                            width: parent.width; height: BarConfig.sp(120); radius: BarConfig.sp(12)
                            color: Colors.surfaceContainerHigh
                            border.color: Colors.popupBorder; border.width: 1

                            Item {
                                anchors { fill: parent; margins: BarConfig.sp(14) }
                                Text {
                                    id: npLbl
                                    anchors { top: parent.top; left: parent.left }
                                    text: "NOW PLAYING"; color: Colors.primary; font.pixelSize: BarConfig.fsSm; font.weight: Font.Bold; font.letterSpacing: 1.2
                                }
                                Text {
                                    visible: drawerWin.activePlayer === null
                                    anchors.centerIn: parent
                                    text: "No media playing"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd; opacity: 0.6
                                }
                                Column {
                                    visible: drawerWin.activePlayer !== null
                                    anchors { top: npLbl.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: BarConfig.sp(8) }
                                    spacing: BarConfig.sp(4)
                                    Text {
                                        text: drawerWin.activePlayer?.trackTitle || ""
                                        color: Colors.colOnSurface; font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                                        elide: Text.ElideRight; width: parent.width
                                    }
                                    Text {
                                        text: drawerWin.activePlayer?.trackArtist || ""
                                        color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                                        elide: Text.ElideRight; width: parent.width
                                    }
                                    Rectangle {
                                        width: parent.width; height: BarConfig.sp(4); radius: BarConfig.sp(2); color: Colors.surfaceContainer
                                        Rectangle { width: parent.width * 0.4; height: parent.height; radius: parent.radius; color: Colors.primary }
                                    }
                                    Row {
                                        spacing: BarConfig.sp(12)
                                        Text {
                                            font.pixelSize: Math.round(16 * BarConfig.uiScale); font.family: "Symbols Nerd Font Mono"; color: Colors.colOnSurfaceVariant; text: ""
                                            opacity: drawerWin.activePlayer?.canGoPrevious ?? false ? 1 : 0.3
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: drawerWin.activePlayer?.previous() }
                                        }
                                        Rectangle {
                                            width: BarConfig.sp(32); height: BarConfig.sp(22); radius: BarConfig.sp(11); color: Colors.primary
                                            Text {
                                                anchors.centerIn: parent; font.pixelSize: BarConfig.fsMd; font.family: "Symbols Nerd Font Mono"; color: Colors.colOnPrimary
                                                text: drawerWin.activePlayer?.isPlaying ? "" : ""
                                            }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: drawerWin.activePlayer?.togglePlaying() }
                                        }
                                        Text {
                                            font.pixelSize: Math.round(16 * BarConfig.uiScale); font.family: "Symbols Nerd Font Mono"; color: Colors.colOnSurfaceVariant; text: ""
                                            opacity: drawerWin.activePlayer?.canGoNext ?? false ? 1 : 0.3
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: drawerWin.activePlayer?.next() }
                                        }
                                    }
                                }
                            }
                        }

                        // ── Workspaces ────────────────────────────────────────────
                        Rectangle {
                            width: parent.width; radius: BarConfig.sp(12)
                            color: Colors.surfaceContainerHigh
                            border.color: Colors.popupBorder; border.width: 1
                            implicitHeight: wsInner.implicitHeight + 28

                            Item {
                                id: wsInner
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: BarConfig.sp(14) }
                                implicitHeight: wsLbl.height + 10 + wsRow.height

                                Text {
                                    id: wsLbl
                                    text: "WORKSPACES"; color: Colors.primary; font.pixelSize: BarConfig.fsSm; font.weight: Font.Bold; font.letterSpacing: 1.2
                                }
                                Row {
                                    id: wsRow
                                    anchors { top: wsLbl.bottom; left: parent.left; right: parent.right; topMargin: BarConfig.sp(10) }
                                    spacing: BarConfig.sp(6)
                                    Repeater {
                                        model: 5
                                        Rectangle {
                                            id: wsTile
                                            required property int index
                                            readonly property int wsId: index + 1
                                            readonly property bool isActive: { const ws = Hyprland.focusedMonitor?.activeWorkspace; return ws ? ws.id === wsId : wsId === 1 }
                                            readonly property var  wsObj: Hyprland.workspaces.values.find(w => w.id === wsTile.wsId) ?? null
                                            readonly property int  winCount: wsTile.wsObj?.windows ?? 0
                                            width: (wsRow.width - 24) / 5; height: BarConfig.sp(44); radius: BarConfig.sp(8)
                                            color: wsTile.isActive ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18) : Colors.surfaceContainer
                                            border.color: wsTile.isActive ? Colors.primary : Colors.popupBorder; border.width: wsTile.isActive ? 2 : 1
                                            Behavior on color       { ColorAnimation { duration: 120 } }
                                            Behavior on border.color { ColorAnimation { duration: 120 } }

                                            Column {
                                                anchors.centerIn: parent; spacing: BarConfig.sp(4)
                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: "0" + wsTile.wsId; font.pixelSize: BarConfig.fs; font.weight: Font.Medium
                                                    color: wsTile.isActive ? Colors.primary : Colors.colOnSurfaceVariant
                                                }
                                                // Window count dots (up to 4)
                                                Row {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    spacing: BarConfig.sp(3); visible: wsTile.winCount > 0
                                                    Repeater {
                                                        model: Math.min(wsTile.winCount, 4)
                                                        Rectangle {
                                                            required property int index
                                                            width: BarConfig.sp(4); height: BarConfig.sp(4); radius: BarConfig.sp(2)
                                                            color: wsTile.isActive ? Colors.primary : Colors.colOnSurfaceVariant
                                                            opacity: 0.7
                                                        }
                                                    }
                                                }
                                            }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Hyprland.dispatch("workspace " + wsTile.wsId) }
                                        }
                                    }
                                }
                            }
                        }

                        // ── Quick stat cards ──────────────────────────────────────
                        component MiniStat: Rectangle {
                            required property string cardLabel
                            required property string mainVal
                            required property string subVal
                            required property real   fillRatio
                            radius: BarConfig.sp(12); color: Colors.surfaceContainerHigh
                            border.color: Colors.popupBorder; border.width: 1
                            Column {
                                anchors { fill: parent; margins: BarConfig.sp(12) }
                                spacing: BarConfig.sp(4)
                                Text { text: cardLabel; color: Colors.primary; font.pixelSize: BarConfig.fsXs; font.weight: Font.Bold; font.letterSpacing: 1; opacity: 0.8 }
                                Text { text: mainVal; color: Colors.colOnSurface; font.pixelSize: Math.round(20 * BarConfig.uiScale); font.weight: Font.Light }
                                Text { text: subVal; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm; elide: Text.ElideRight; width: parent.width }
                                Rectangle {
                                    width: parent.width; height: BarConfig.sp(4); radius: BarConfig.sp(2); color: Colors.surfaceContainer
                                    Rectangle {
                                        width: Math.max(0, Math.min(1, fillRatio)) * parent.width
                                        height: parent.height; radius: parent.radius
                                        color: fillRatio > 0.85 ? Colors.error : Colors.primary
                                        Behavior on width { NumberAnimation { duration: 300 } }
                                    }
                                }
                            }
                        }

                        Grid {
                            width: parent.width; columns: 2; spacing: BarConfig.sp(10)
                            MiniStat {
                                width: (parent.width - 10) / 2; height: BarConfig.sp(90)
                                cardLabel: "CPU"; mainVal: dashTab.cpuPct + "%"; subVal: "processor"
                                fillRatio: dashTab.cpuPct / 100
                            }
                            MiniStat {
                                width: (parent.width - 10) / 2; height: BarConfig.sp(90)
                                cardLabel: "RAM"; mainVal: dashTab.ramUsed.toFixed(1) + " GB"; subVal: "of " + dashTab.ramTotal.toFixed(1) + " GB"
                                fillRatio: dashTab.ramTotal > 0 ? dashTab.ramUsed / dashTab.ramTotal : 0
                            }
                            MiniStat {
                                width: (parent.width - 10) / 2; height: BarConfig.sp(90)
                                cardLabel: "STORAGE"; mainVal: dashTab.storageUsed || "--"; subVal: "of " + (dashTab.storageTotal || "--")
                                fillRatio: { if (!dashTab.storageUsed || !dashTab.storageTotal) return 0; return parseFloat(dashTab.storageUsed) / parseFloat(dashTab.storageTotal) }
                            }
                        }

                        Item { height: BarConfig.sp(8) }
                    }
                }
                // Scrollbar
                Rectangle {
                    visible: dashFlick.contentHeight > dashFlick.height
                    anchors.right: parent.right; anchors.rightMargin: BarConfig.sp(4)
                    readonly property real _r: BarConfig.sp(14)
                    readonly property real _thumbH: dashFlick.visibleArea.heightRatio * dashFlick.height
                    y: Math.max(dashFlick.y + _r, Math.min(dashFlick.y + dashFlick.height - _thumbH - _r,
                                dashFlick.y + dashFlick.visibleArea.yPosition * dashFlick.height))
                    width: BarConfig.sp(3); height: _thumbH
                    radius: BarConfig.sp(2); color: Colors.outline; opacity: 0.5; z: 5
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // Tab 2: NOTIFICATIONS
            // ═══════════════════════════════════════════════════════════════
            Item {
                id: drawerNotifList
                anchors.fill: parent
                visible: ShellState.drawerTab === 2

                property var _seenIds: ({})

                function clearAll() {
                    _seenIds = {}
                    // Fade out whole list then dismiss
                    notifFadeOut.restart()
                }

                SequentialAnimation {
                    id: notifFadeOut
                    NumberAnimation { target: notifFlick; property: "opacity"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                    ScriptAction { script: { NotificationService.dismissAll(); notifFlick.opacity = 1 } }
                }

                // Header row with Clear
                Item {
                    id: notifHdr
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: BarConfig.sp(40)

                    Text {
                        anchors { left: parent.left; leftMargin: BarConfig.sp(14); verticalCenter: parent.verticalCenter }
                        text: "NOTIFICATIONS"
                        color: Colors.colOnSurfaceVariant
                        font.pixelSize: BarConfig.fsSm; font.weight: Font.Medium; font.letterSpacing: 1.2
                    }

                    Row {
                        anchors { right: parent.right; rightMargin: BarConfig.sp(14); verticalCenter: parent.verticalCenter }
                        height: notifHdr.height
                        spacing: BarConfig.sp(12)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Clear"
                            color: Colors.primary; font.pixelSize: BarConfig.fsMd
                            visible: NotificationService.notifications.length > 0
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: drawerNotifList.clearAll() }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: NotificationService.unreadCount > 0
                            width: Math.max(BarConfig.sp(18), cntTxt.implicitWidth + BarConfig.sp(8))
                            height: BarConfig.sp(18); radius: BarConfig.sp(9)
                            color: Colors.primary
                            Text { id: cntTxt; anchors.centerIn: parent; text: NotificationService.unreadCount; color: Colors.colOnPrimary; font.pixelSize: BarConfig.fsSm; font.weight: Font.Bold }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⚙"
                            color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.sp(16)
                            opacity: 0.7
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                onClicked: BarConfig.openBarSettings(drawerWin.screen?.name ?? BarConfig.lastPopupScreen, 3)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors { top: notifHdr.bottom; left: parent.left; right: parent.right; leftMargin: BarConfig.sp(14); rightMargin: BarConfig.sp(14) }
                    height: 1; color: Colors.popupBorder; opacity: 0.7
                }

                // "No notifications" centered in the body area
                Text {
                    anchors { top: notifHdr.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "No notifications"
                    color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                    visible: NotificationService.notifications.length === 0
                }

                Flickable {
                    id: notifFlick
                    anchors { top: notifHdr.bottom; topMargin: BarConfig.sp(5); left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: BarConfig.sp(8) }
                    contentHeight: notifCol.implicitHeight
                    clip: true
                    visible: NotificationService.notifications.length > 0

                    Column {
                        id: notifCol
                        anchors { left: parent.left; right: parent.right; leftMargin: BarConfig.sp(8); rightMargin: BarConfig.sp(8) }
                        spacing: BarConfig.sp(6); topPadding: 4

                        Repeater {
                            model: NotificationService.notifications
                            // Outer Item controls height (collapses on exit); inner Rectangle is the visual card
                            delegate: Item {
                                id: nCardWrap
                                required property int index
                                required property var modelData
                                width: notifCol.width
                                // _fullH drives the animated height
                                property real _fullH: nCardRect.implicitHeight
                                property real _animH: 0
                                height: _animH
                                clip: true
                                property bool _removing: false

                                function doRemove() {
                                    if (_removing) return
                                    _removing = true
                                    nCardRemoveAnim.start()
                                }

                                // Enter: height 0→full then fade in
                                Component.onCompleted: {
                                    if (!drawerNotifList._seenIds[nCardWrap.modelData.id]) {
                                        drawerNotifList._seenIds[nCardWrap.modelData.id] = true
                                        drawerNotifList._seenIdsChanged()
                                        nCardRect.opacity = 0
                                        Qt.callLater(() => nCardEnterAnim.start())
                                    } else {
                                        _animH = Qt.binding(() => _fullH + notifCol.spacing)
                                    }
                                }

                                SequentialAnimation {
                                    id: nCardEnterAnim
                                    NumberAnimation { target: nCardWrap; property: "_animH"; from: 0; to: nCardWrap._fullH + notifCol.spacing; duration: 200; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: nCardRect; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                                    ScriptAction { script: nCardWrap._animH = Qt.binding(() => nCardWrap._fullH + notifCol.spacing) }
                                }

                                // Exit: fade out + collapse height
                                SequentialAnimation {
                                    id: nCardRemoveAnim
                                    NumberAnimation { target: nCardRect; property: "opacity"; to: 0; duration: 140; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: nCardWrap; property: "_animH"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                                    ScriptAction { script: NotificationService.dismiss(nCardWrap.modelData.id) }
                                }

                                Rectangle {
                                    id: nCardRect
                                    width: nCardWrap.width
                                    implicitHeight: nCardCol.implicitHeight + BarConfig.sp(20)
                                    radius: BarConfig.sp(8)
                                    color: Colors.surfaceContainerHigh
                                    border.color: Colors.popupBorder; border.width: 1

                                    Column {
                                        id: nCardCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: BarConfig.sp(12); rightMargin: BarConfig.sp(32); topMargin: BarConfig.sp(10) }
                                        spacing: BarConfig.sp(3)
                                        Text { width: parent.width; text: nCardWrap.modelData.app + "  ·  " + nCardWrap.modelData.timestamp; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm; elide: Text.ElideRight }
                                        Text { width: parent.width; text: nCardWrap.modelData.summary; color: Colors.colOnSurface; font.pixelSize: BarConfig.fs; font.weight: Font.Medium; elide: Text.ElideRight }
                                        Text { width: parent.width; text: nCardWrap.modelData.body; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd; elide: Text.ElideRight; visible: nCardWrap.modelData.body !== "" }
                                    }

                                    Text {
                                        anchors { top: parent.top; right: parent.right; topMargin: BarConfig.sp(6); rightMargin: BarConfig.sp(8) }
                                        text: "×"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsLg
                                        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: nCardWrap.doRemove() }
                                    }
                                }
                            }
                        }
                    }
                }
                // Scrollbar
                Rectangle {
                    visible: notifFlick.contentHeight > notifFlick.height
                    anchors.right: parent.right; anchors.rightMargin: BarConfig.sp(4)
                    readonly property real _r: BarConfig.sp(14)
                    readonly property real _thumbH: notifFlick.visibleArea.heightRatio * notifFlick.height
                    y: Math.max(notifFlick.y + _r, Math.min(notifFlick.y + notifFlick.height - _thumbH - _r,
                                notifFlick.y + notifFlick.visibleArea.yPosition * notifFlick.height))
                    width: BarConfig.sp(3); height: _thumbH
                    radius: BarConfig.sp(2); color: Colors.outline; opacity: 0.5; z: 5
                }
            }
        }
    }
}

