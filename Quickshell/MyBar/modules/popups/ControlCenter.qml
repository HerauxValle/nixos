pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../../config"
import "../../services"

Rectangle {
    id: root
    property string barScreenName: ""
    implicitWidth: BarConfig.sp(380)
    // Fill the Loader (which fills the popup host with its fixed height).
    // The Flickable inside makes the content scrollable within that height.
    height: parent?.height ?? 460
    radius: BarConfig.sp(14)
    color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)
    border.color: Colors.popupBorder
    border.width: 1

    // Absorb all clicks inside so they don't fall through to the backdrop
    MouseArea { anchors.fill: parent; onClicked: {} }

    // ── MPRIS ──────────────────────────────────────────────────────────────────────
    readonly property MprisPlayer activePlayer: {
        const vals = Mpris.players.values
        return vals.find(p => p.isPlaying) ??
               vals.find(p => p.playbackState === MprisPlaybackState.Paused) ?? null
    }

    // ── Audio sink/source indices ──────────────────────────────────────────────────────
    property bool sinkExpanded:   false
    property bool sourceExpanded: false

    property int sinkIdx: {
        const idx = Audio.allSinks.findIndex(s => s === Audio.pwSink)
        return idx < 0 ? 0 : idx
    }
    property int srcIdx: {
        const idx = Audio.allSources.findIndex(s => s === Audio.pwSource)
        return idx < 0 ? 0 : idx
    }

    // ── Mic mute via wpctl ────────────────────────────────────────────────────────
    property bool micMuted: false

    Process {
        id: micMuteProc
        command: ["wpctl", "set-mute", "@DEFAULT_SOURCE@", "toggle"]
        onExited: micCheckProc.running = true
    }
    Process {
        id: micCheckProc
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_SOURCE@ 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.micMuted = text.includes("[MUTED]")
        }
    }
    Timer {
        interval: 3000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: micCheckProc.running = true
    }

    // Per-app stream volume via wpctl (reliable fallback when QML write stalls)
    Process {
        id: streamVolProc
        property string nodeIdStr: "0"
        property int    volPct:    100
        command: ["wpctl", "set-volume", nodeIdStr, String(volPct) + "%"]
    }

    // ── Reusable: mini toggle pill ─────────────────────────────────────────────────────────
    component MiniToggle: Rectangle {
        id: mt
        required property string lbl
        required property bool   chk
        signal toggled()
        implicitWidth: mlbl.implicitWidth + 20; implicitHeight: BarConfig.sp(22)
        radius: height / 2
        color: mt.chk ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.25)
                      : Colors.surfaceContainerHigh
        border.color: mt.chk ? Colors.primary : Colors.outline; border.width: 1
        Behavior on color { ColorAnimation { duration: 100 } }
        Row {
            anchors.centerIn: parent; spacing: BarConfig.sp(4)
            Rectangle {
                width: BarConfig.sp(6); height: BarConfig.sp(6); radius: BarConfig.sp(3); anchors.verticalCenter: parent.verticalCenter
                color: mt.chk ? Colors.primary : Colors.outline
                Behavior on color { ColorAnimation { duration: 100 } }
            }
            Text {
                id: mlbl; text: mt.lbl; font.pixelSize: BarConfig.fs; anchors.verticalCenter: parent.verticalCenter
                color: mt.chk ? Colors.primary : Colors.colOnSurfaceVariant
                Behavior on color { ColorAnimation { duration: 100 } }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mt.toggled() }
    }

    // ── Reusable: divider ──────────────────────────────────────────────────────────────────────────
    component Div: Rectangle {
        implicitWidth: parent?.width ?? 340; implicitHeight: 1
        color: Colors.popupBorder; opacity: 0.8
    }

    // ── Reusable: section label ───────────────────────────────────────────────────────────────────
    component SLabel: Text {
        color: Colors.primary; font.pixelSize: BarConfig.fsSm
        font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.75
    }

    // ── Volume slider ─────────────────────────────────────────────────────────────────────────────
    component VSlider: Item {
        id: sl
        required property real value
        required property real maxVal
        signal moved(real v)
        implicitHeight: BarConfig.sp(20)

        Rectangle {
            id: slT
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: BarConfig.sp(5); radius: BarConfig.sp(3); color: Colors.surfaceContainerHigh
            Rectangle {
                width: Math.min(sl.value / sl.maxVal, 1) * slT.width
                height: parent.height; radius: parent.radius
                color: sl.value > 1.0 ? Colors.error : Colors.primary
                Behavior on width { NumberAnimation { duration: 50 } }
            }
            Rectangle {
                width: BarConfig.sp(16); height: BarConfig.sp(16); radius: BarConfig.sp(8); color: Colors.primary
                anchors.verticalCenter: parent.verticalCenter
                x: Math.min(sl.value / sl.maxVal, 1) * (slT.width - width)
                Behavior on x { NumberAnimation { duration: 50 } }
            }
        }
        MouseArea {
            cursorShape: Qt.PointingHandCursor
            anchors { fill: parent; topMargin: -10; bottomMargin: -10 }
            onPositionChanged: (m) => {
                if (!pressed) return
                const p = mapToItem(slT, m.x, m.y)
                sl.moved(Math.max(0, Math.min(sl.maxVal, (p.x / slT.width) * sl.maxVal)))
            }
            onClicked: (m) => {
                const p = mapToItem(slT, m.x, m.y)
                sl.moved(Math.max(0, Math.min(sl.maxVal, (p.x / slT.width) * sl.maxVal)))
            }
        }
    }

    // ── Inline device picker (expandable) ─────────────────────────────────────────────────────
    component DevicePicker: Item {
        id: dp
        required property string icon
        required property string label
        required property var    devices
        required property int    curIdx
        property bool expanded: false
        signal pick(int idx)

        implicitWidth: parent?.width ?? 340
        implicitHeight: dpHeader.implicitHeight + (dp.expanded ? dpList.implicitHeight : 0)
        clip: true
        Behavior on implicitHeight { NumberAnimation { duration: 120; easing.bezierCurve: Colors.spring } }

        // ── Header row ──────────────────────────────────────────────────────────────────
        Item {
            id: dpHeader
            width: parent.width; implicitHeight: BarConfig.sp(38)

            Item {
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
                Item {
                    id: dpIco
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: BarConfig.sp(22); height: BarConfig.sp(22)
                    Text {
                        anchors.centerIn: parent
                        font.pixelSize: BarConfig.fsLg; font.family: "Symbols Nerd Font Mono"
                        color: Colors.colOnSurfaceVariant; text: dp.icon
                    }
                }
                Column {
                    anchors { left: dpIco.right; leftMargin: BarConfig.sp(6); verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Text {
                        text: dp.label; font.pixelSize: BarConfig.fsXs; font.weight: Font.Medium
                        color: Colors.colOnSurfaceVariant; font.letterSpacing: 1; opacity: 0.75
                    }
                    Text {
                        text: {
                            if (dp.devices.length === 0) return "None"
                            const n = dp.devices[Math.min(dp.curIdx, dp.devices.length - 1)]
                            return (n?.description || n?.name || "Unknown").replace(/\s*\[.*?\]/g, "").trim()
                        }
                        font.pixelSize: BarConfig.fs; color: Colors.colOnSurface
                        elide: Text.ElideRight; width: BarConfig.sp(230)
                    }
                }
            }

            Item {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                implicitWidth: BarConfig.sp(28); implicitHeight: BarConfig.sp(28)
                Text {
                    anchors.centerIn: parent; font.pixelSize: BarConfig.fsMd
                    color: Colors.colOnSurfaceVariant
                    text: dp.expanded ? "\u25B4" : "\u25BE"
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: dp.expanded = !dp.expanded && dp.devices.length > 1
                }
            }

            MouseArea {
                cursorShape: Qt.PointingHandCursor
                anchors { fill: parent; rightMargin: BarConfig.sp(32) }
                onClicked: if (dp.devices.length > 1) dp.expanded = !dp.expanded
            }
        }

        // ── Expanded device list ────────────────────────────────────────────────────────────────
        Column {
            id: dpList
            y: dpHeader.implicitHeight
            width: parent.width
            spacing: 0

            Repeater {
                model: dp.devices.length
                Item {
                    required property int index
                    width: parent.width; height: BarConfig.sp(34)

                    Rectangle {
                        anchors { fill: parent; leftMargin: BarConfig.sp(8); rightMargin: BarConfig.sp(8); topMargin: 1 }
                        radius: BarConfig.sp(8)
                        color: dp.curIdx === index
                               ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18)
                               : "transparent"

                        Row {
                            anchors { left: parent.left; right: parent.right
                                      leftMargin: BarConfig.sp(10); rightMargin: BarConfig.sp(10)
                                      verticalCenter: parent.verticalCenter }
                            spacing: BarConfig.sp(8)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: dp.curIdx === index ? "\u2713" : "  "
                                font.pixelSize: BarConfig.fsMd; color: Colors.primary
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (index >= dp.devices.length) return ""
                                    const n = dp.devices[index]
                                    return (n?.description || n?.name || "").replace(/\s*\[.*?\]/g, "").trim()
                                }
                                font.pixelSize: BarConfig.fsMd; color: Colors.colOnSurface
                                elide: Text.ElideRight
                                width: parent.width - 30
                            }
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { dp.pick(index); dp.expanded = false }
                        }
                    }
                }
            }
        }
    }

    // ── Signal bars ───────────────────────────────────────────────────────────────────────────────
    component SignalBars: Item {
        id: bars
        required property int signal
        implicitWidth: BarConfig.sp(22); implicitHeight: BarConfig.sp(16)
        Repeater {
            model: 4
            Rectangle {
                required property int index
                width: BarConfig.sp(4); height: 4 + index * 3; radius: 1
                x: index * 6; anchors.bottom: bars.bottom
                color: bars.signal > index * 25 ? Colors.primary : Colors.outlineVariant
            }
        }
    }

    // ── Header ─────────────────────────────────────────────────────────────────────────────────
    Item {
        id: hdr
        width: parent.width; height: BarConfig.sp(46); z: 2

        Text {
            anchors { left: parent.left; leftMargin: BarConfig.sp(16); verticalCenter: parent.verticalCenter }
            text: "Control Center"; color: Colors.colOnSurface
            font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
        }
        Text {
            anchors { right: parent.right; rightMargin: BarConfig.sp(14); verticalCenter: parent.verticalCenter }
            text: "\u2715"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fs
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.closePopup() }
        }

        Div {
            width: parent.width
            anchors.bottom: parent.bottom
        }
    }

    // ── Scrollable body ──────────────────────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors { top: hdr.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: BarConfig.sp(14) }
        contentWidth: width
        contentHeight: body.implicitHeight + 16
        clip: true

        Column {
            id: body
            width: flick.width - 28
            x: 14
            y: 10
            spacing: BarConfig.sp(10)

            // ── WiFi + BT + Airplane tiles ───────────────────────────────────────────────────────
            Row {
                id: radioRow
                width: parent.width; spacing: BarConfig.sp(6)

                // Shared mini toggle
                component RadioToggle: Rectangle {
                    id: rt
                    required property bool on
                    property bool _loaded: false
                    Timer { interval: 600; running: true; onTriggered: rt._loaded = true }
                    signal toggled()
                    width: BarConfig.sp(26); height: BarConfig.sp(14); radius: BarConfig.sp(7)
                    anchors.verticalCenter: parent.verticalCenter
                    color: rt.on ? Colors.primary : Colors.surfaceContainerHigh
                    border.color: rt.on ? Colors.primary : Colors.outline; border.width: 1
                    Behavior on color { ColorAnimation { duration: rt._loaded ? 120 : 0 } }
                    Rectangle {
                        width: BarConfig.sp(10); height: BarConfig.sp(10); radius: BarConfig.sp(5); anchors.verticalCenter: parent.verticalCenter
                        color: rt.on ? Colors.colOnPrimary : Colors.outline
                        x: rt.on ? parent.width - width - 2 : 2
                        Behavior on x     { NumberAnimation { duration: rt._loaded ? 180 : 0; easing.bezierCurve: Colors.spring } }
                        Behavior on color { ColorAnimation  { duration: rt._loaded ? 120 : 0 } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; z: 1; onClicked: rt.toggled() }
                }

                // WiFi tile
                Rectangle {
                    width: (radioRow.width - 12) / 3; height: BarConfig.sp(74); radius: BarConfig.sp(12)
                    color: Network.wifiRadioOn
                           ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.12)
                           : Colors.surfaceContainerHigh
                    border.color: Network.wifiRadioOn ? Colors.primary : Colors.popupBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.togglePopup("wifi", root.barScreenName) }
                    Column {
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: BarConfig.sp(9) }
                        spacing: BarConfig.sp(4)
                        Row {
                            spacing: BarConfig.sp(5)
                            Text {
                                font.pixelSize: BarConfig.fsLg; font.family: "Symbols Nerd Font Mono"
                                color: Network.wifiOn ? Colors.primary : Colors.outline; text: ""
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            RadioToggle { on: Network.wifiRadioOn; onToggled: Network.toggleWifi() }
                        }
                        Text {
                            width: parent.width
                            text: !Network.wifiRadioOn ? "Off"
                                : Network.wifiSSID !== "" ? Network.wifiSSID : "No network"
                            font.pixelSize: BarConfig.fsSm; font.weight: Font.Medium
                            color: Colors.colOnSurface; elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: Network.wifiOn ? (Network.wifiIP || "Connected") : "Wi-Fi"
                            font.pixelSize: BarConfig.fsXs; color: Colors.colOnSurfaceVariant; opacity: 0.7; elide: Text.ElideRight
                        }
                    }
                    Text {
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: BarConfig.sp(6); bottomMargin: BarConfig.sp(5) }
                        text: "›"; font.pixelSize: BarConfig.fs; color: Colors.primary; opacity: 0.65
                    }
                }

                // BT tile
                Rectangle {
                    id: btTile
                    property bool _loaded: false
                    Timer { interval: 600; running: true; onTriggered: btTile._loaded = true }
                    width: (radioRow.width - 12) / 3; height: BarConfig.sp(74); radius: BarConfig.sp(12)
                    color: Network.btOn
                           ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.12)
                           : Colors.surfaceContainerHigh
                    border.color: Network.btOn ? Colors.primary : Colors.popupBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: btTile._loaded ? 120 : 0 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.togglePopup("bluetooth", root.barScreenName) }
                    Column {
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: BarConfig.sp(9) }
                        spacing: BarConfig.sp(4)
                        Row {
                            spacing: BarConfig.sp(5)
                            Text {
                                font.pixelSize: BarConfig.fsLg; font.family: "Symbols Nerd Font Mono"
                                color: Network.btOn ? Colors.primary : Colors.outline; text: ""
                                Behavior on color { ColorAnimation { duration: btTile._loaded ? 120 : 0 } }
                            }
                            RadioToggle { on: Network.btOn; onToggled: Network.toggleBluetooth() }
                        }
                        Text {
                            width: parent.width
                            text: !Network.btOn ? "Off" : (Network.btDevice || "No device")
                            font.pixelSize: BarConfig.fsSm; font.weight: Font.Medium
                            color: Colors.colOnSurface; elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: Network.btOn ? (Network.btDevice ? "Connected" : "Bluetooth") : "Bluetooth"
                            font.pixelSize: BarConfig.fsXs; color: Colors.colOnSurfaceVariant; opacity: 0.7
                        }
                    }
                    Text {
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: BarConfig.sp(6); bottomMargin: BarConfig.sp(5) }
                        text: "›"; font.pixelSize: BarConfig.fs; color: Colors.primary; opacity: 0.65
                    }
                }

                // Airplane mode tile
                Rectangle {
                    width: (radioRow.width - 12) / 3; height: BarConfig.sp(74); radius: BarConfig.sp(12)
                    color: Network.airplaneMode
                           ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.12)
                           : Colors.surfaceContainerHigh
                    border.color: Network.airplaneMode ? Colors.primary : Colors.popupBorder; border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: BarConfig.sp(6); bottomMargin: BarConfig.sp(5) }
                        text: "›"; font.pixelSize: BarConfig.fs; color: Colors.primary; opacity: 0.65
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                            onClicked: BarConfig.togglePopup("airplanesettings", root.barScreenName)
                        }
                    }
                    Column {
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: BarConfig.sp(9) }
                        spacing: BarConfig.sp(4)
                        Row {
                            spacing: BarConfig.sp(5)
                            Text {
                                font.pixelSize: BarConfig.fsLg; font.family: "Symbols Nerd Font Mono"
                                color: Network.airplaneMode ? Colors.primary : Colors.outline; text: ""
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            RadioToggle { on: Network.airplaneMode; onToggled: Network.toggleAirplaneMode() }
                        }
                        Text {
                            text: Network.airplaneMode ? "Airplane" : "Normal"
                            font.pixelSize: BarConfig.fsSm; font.weight: Font.Medium; color: Colors.colOnSurface
                        }
                        Text {
                            text: Network.airplaneMode ? "Radios off" : "Airplane"
                            font.pixelSize: BarConfig.fsXs; color: Colors.colOnSurfaceVariant; opacity: 0.7
                        }
                    }
                }
            }
            Div { width: parent.width }

            // ── Audio output device picker ───────────────────────────────────────────────────────
            DevicePicker {
                width: parent.width
                icon: "\uF028"
                label: "OUTPUT"
                devices: Audio.allSinks
                curIdx: root.sinkIdx
                expanded: root.sinkExpanded
                onExpandedChanged: root.sinkExpanded = expanded
                onPick: (idx) => Audio.setDefaultSink(Audio.allSinks[idx])
            }

            // ── Audio input device picker ────────────────────────────────────────────────────────
            DevicePicker {
                width: parent.width
                icon: "\uF130"
                label: "INPUT"
                devices: Audio.allSources
                curIdx: root.srcIdx
                expanded: root.sourceExpanded
                onExpandedChanged: root.sourceExpanded = expanded
                onPick: (idx) => Audio.setDefaultSource(Audio.allSources[idx])
            }

            // ── Output volume slider ──────────────────────────────────────────────
            Div { width: parent.width }
            Item {
                width: parent.width; height: BarConfig.sp(32)
                Text {
                    id: vIco
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: BarConfig.sp(20); horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: BarConfig.fsLg; font.family: "Symbols Nerd Font Mono"
                    color: Audio.muted ? Colors.outline : Colors.primary
                    text: Audio.muted        ? "\uF026"
                        : Audio.volume > 0.5 ? "\uF028"
                        :                      "\uF027"
                    Behavior on color { ColorAnimation { duration: 100 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Audio.toggleMute() }
                }
                VSlider {
                    anchors { left: vIco.right; leftMargin: BarConfig.sp(8); right: vPct.left; rightMargin: BarConfig.sp(6); verticalCenter: parent.verticalCenter }
                    value: Audio.volume; maxVal: 1.5
                    onMoved: (v) => Audio.setVolume(v)
                }
                Text {
                    id: vPct
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: BarConfig.sp(32); horizontalAlignment: Text.AlignRight
                    text: Math.round(Audio.volume * 100) + "%"
                    color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                }
            }

            // ── Quick launch — Dashboard / Drawer / Launcher ─────────────
            Div { width: parent.width }

            Row {
                width: parent.width; spacing: BarConfig.sp(6)

                component QBtn: Rectangle {
                    id: qb
                    required property string label
                    required property string icon
                    signal tapped()
                    property int btnW: (parent?.width ?? 330)
                    width: (btnW - 18) / 4; height: BarConfig.sp(36); radius: BarConfig.sp(8)
                    color: Colors.surfaceContainerHigh
                    border.color: Colors.popupBorder; border.width: 1
                    Column {
                        anchors.centerIn: parent; spacing: BarConfig.sp(2)
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: qb.icon; font.pixelSize: BarConfig.fsMd
                            font.family: "Symbols Nerd Font Mono"
                            color: Colors.colOnSurfaceVariant
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: qb.label; font.pixelSize: BarConfig.fsXs
                            color: Colors.colOnSurfaceVariant
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: qb.tapped()
                    }
                }

                QBtn {
                    label: "Drawer"; icon: "\uF0c9"
                    btnW: parent.width
                    onTapped: {
                        if (ShellState.drawerOpen && ShellState.drawerTab === 0) ShellState.closeDrawer()
                        else ShellState.openDrawerTab(0)
                    }
                }
                QBtn {
                    label: "Dashboard"; icon: "\uF00a"
                    btnW: parent.width
                    onTapped: {
                        if (ShellState.drawerOpen && ShellState.drawerTab === 1) ShellState.closeDrawer()
                        else ShellState.openDrawerTab(1)
                    }
                }
                QBtn {
                    label: "Notifications"; icon: "\uF0F3"
                    btnW: parent.width
                    onTapped: {
                        if (ShellState.drawerOpen && ShellState.drawerTab === 2) ShellState.closeDrawer()
                        else ShellState.openDrawerTab(2)
                    }
                }
                QBtn {
                    label: "Launcher"; icon: "\uF002"
                    btnW: parent.width
                    onTapped: ShellState.toggleLauncher()
                }
            }

            // ── Settings links ─────────────────────────────────────────────────────────────────────
            Item {
                width: parent.width; height: BarConfig.sp(28)
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "\u2699 Advanced Settings \u203a"
                    color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: BarConfig.openBarSettings(root.barScreenName)
                    }
                }
            }
        }
    }

    // Scrollbar — sibling of Flickable, tracks flick.y + scroll offset
    Rectangle {
        visible: flick.contentHeight > flick.height
        anchors.right: parent.right; anchors.rightMargin: BarConfig.sp(4)
        readonly property real _r: BarConfig.sp(14)
        readonly property real _thumbH: flick.visibleArea.heightRatio * flick.height
        y: Math.max(flick.y, Math.min(flick.y + flick.height - _thumbH - _r,
                    flick.y + flick.visibleArea.yPosition * flick.height))
        width: BarConfig.sp(3); height: _thumbH
        radius: BarConfig.sp(2); color: Colors.outline; opacity: 0.5
        z: 5
    }
}