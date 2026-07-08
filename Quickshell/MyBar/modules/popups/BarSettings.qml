pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../../config"

// Detailed bar settings — tabbed, accessed from Control Centre.
Rectangle {
    id: root
    property string barScreenName: ""
    implicitWidth: BarConfig.sp(360)
    height: parent?.height ?? 460
    radius: BarConfig.sp(16)
    color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)
    border.color: Colors.popupBorder
    border.width: 1
    focus: true
    Keys.onEscapePressed: BarConfig.closePopup()

    // Tabs list — add new tabs here, content below
    readonly property var _tabs: ["APPEARANCE", "BAR", "WIDGETS", "NOTIFICATIONS", "KEYBINDS"]

    property int activeTab: BarConfig.barSettingsTab
    onActiveTabChanged: {
        BarConfig.barSettingsTab = activeTab
        if (_slideDir !== 0) contentSlideAnim.restart()
    }

    property int _winStart: (activeTab - 1 + _tabs.length) % _tabs.length
    property int _slideDir: 0   // -1 = going left, +1 = going right

    property int blurStrength: 8
    property bool _accentApplied: false
    Timer { id: accentFlashTimer; interval: 900; onTriggered: root._accentApplied = false }

    Process { id: blurProc; command: ["hyprctl", "keyword", "decoration:blur:size", "8"] }

    // ── Reusable sub-components ───────────────────────────────────────────

    component SLabel: Text {
        color: Colors.primary
        font.pixelSize: BarConfig.fsMd
        font.weight: Font.Medium
        font.letterSpacing: 1
        opacity: 1.0
    }

    component HR: Rectangle {
        implicitWidth: parent?.width ?? 300
        implicitHeight: 1
        color: Colors.outlineVariant
        opacity: 0.5
    }

    component Btn: Rectangle {
        id: btn
        required property string lbl
        required property bool   active
        signal pick()

        implicitWidth:  blbl.implicitWidth + 18
        implicitHeight: BarConfig.sp(28)
        radius: height / 2
        color: btn.active ? Colors.primary : Colors.surfaceContainerHigh
        border.color: btn.active ? Colors.primary : Colors.outline
        border.width: 1
        Behavior on color  { ColorAnimation { duration: 150 } }

        Text {
            id: blbl
            anchors.centerIn: parent
            text: btn.lbl
            color: btn.active ? Colors.colOnPrimary : Colors.colOnSurfaceVariant
            font.pixelSize: BarConfig.fsMd
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: btn.pick() }
    }

    component Toggle: Item {
        id: tog
        property bool checked: false
        signal toggled(bool v)

        implicitWidth: BarConfig.sp(38); implicitHeight: BarConfig.sp(22)

        Rectangle {
            anchors.fill: parent; radius: height / 2
            color: tog.checked ? Colors.primary : Colors.surfaceContainerHigh
            border.color: tog.checked ? Colors.primary : Colors.outline
            border.width: 1
            Behavior on color { ColorAnimation { duration: 160 } }

            Rectangle {
                width: BarConfig.sp(16); height: BarConfig.sp(16); radius: BarConfig.sp(8)
                color: tog.checked ? Colors.colOnPrimary : Colors.outline
                anchors.verticalCenter: parent.verticalCenter
                x: tog.checked ? parent.width - width - 3 : 3
                Behavior on x     { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
                Behavior on color { ColorAnimation  { duration: 160 } }
            }
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: { tog.checked = !tog.checked; tog.toggled(tog.checked) }
        }
    }

    component SRow: Item {
        id: srow
        required property string label
        default property alias children: rightSlot.data
        implicitWidth: parent?.width ?? 320
        implicitHeight: Math.max(28, rightSlot.implicitHeight + 6)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: srow.label
            color: Colors.colOnSurface
            font.pixelSize: BarConfig.fs
        }
        Item {
            id: rightSlot
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }

    component SimpleSlider: Item {
        id: ssl
        required property real minVal
        required property real maxVal
        required property real value
        signal moved(real v)

        implicitWidth: BarConfig.sp(140); implicitHeight: BarConfig.sp(20)

        Rectangle {
            id: ssTrack
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: BarConfig.sp(4); radius: BarConfig.sp(2)
            color: Colors.outlineVariant

            Rectangle {
                width: (ssl.value - ssl.minVal) / (ssl.maxVal - ssl.minVal) * ssTrack.width
                height: parent.height; radius: parent.radius
                color: Colors.primary
            }
            Rectangle {
                width: BarConfig.sp(14); height: BarConfig.sp(14); radius: BarConfig.sp(7)
                color: Colors.primary
                anchors.verticalCenter: parent.verticalCenter
                x: (ssl.value - ssl.minVal) / (ssl.maxVal - ssl.minVal) * (ssTrack.width - width)
                Behavior on x { NumberAnimation { duration: 60 } }
            }
        }

        MouseArea {
            anchors { fill: parent; topMargin: -8; bottomMargin: -8 }
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: (m) => {
                if (!pressed) return
                const p = mapToItem(ssTrack, m.x, m.y)
                ssl.moved(ssl.minVal + Math.max(0, Math.min(1, p.x / ssTrack.width)) * (ssl.maxVal - ssl.minVal))
            }
            onClicked: (m) => {
                const p = mapToItem(ssTrack, m.x, m.y)
                ssl.moved(ssl.minVal + Math.max(0, Math.min(1, p.x / ssTrack.width)) * (ssl.maxVal - ssl.minVal))
            }
        }
    }

    // ── Header ────────────────────────────────────────────────────────────
    Item {
        id: hdr
        width: parent.width
        height: BarConfig.sp(50)
        z: 2

        Item {
            anchors { left: parent.left; right: parent.right; leftMargin: BarConfig.sp(16); rightMargin: BarConfig.sp(16) }
            anchors.verticalCenter: parent.verticalCenter

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: BarConfig.sp(8)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "←"
                    color: Colors.colOnSurfaceVariant
                    font.pixelSize: BarConfig.fsLg
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: BarConfig.togglePopup("controlcenter", root.barScreenName)
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Advanced Settings"
                    color: Colors.colOnSurface
                    font.pixelSize: BarConfig.fsMd; font.weight: Font.Medium
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                color: Colors.colOnSurfaceVariant
                font.pixelSize: BarConfig.fs
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: BarConfig.closePopup() }
            }
        }

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Colors.outlineVariant; opacity: 0.4 }
    }

    // ── Tab bar: < tab tab > sliding window ───────────────────────────────
    Item {
        id: tabBar
        anchors { top: hdr.bottom; left: parent.left; right: parent.right }
        height: BarConfig.sp(40)
        z: 2

        readonly property int _btnSz: height - BarConfig.sp(8)
        // 3 visible tabs + 2 gaps between them; arrows take _btnSz + sp(8) margin each side
        readonly property int _tabW: Math.floor((width - _btnSz * 2 - BarConfig.sp(8) * 2 - BarConfig.sp(4) * 2 - BarConfig.sp(2) * 2) / 3)
        readonly property int _n: root._tabs.length

        // _winStart: index of left-most visible tab (circular, so slots show [_winStart, _winStart+1, _winStart+2] mod n)
        // activeTab is always the middle slot: _winStart+1 mod n
        function rotate(delta) {
            if (delta === 0) return
            root._slideDir = delta > 0 ? 1 : -1
            root._winStart = ((root._winStart + delta) % _n + _n) % _n
            root.activeTab = (root._winStart + 1) % _n
        }

        // Prev arrow
        Rectangle {
            id: prevBtn
            anchors { left: parent.left; leftMargin: BarConfig.sp(8); verticalCenter: parent.verticalCenter }
            width: tabBar._btnSz; height: tabBar._btnSz
            radius: BarConfig.sp(6)
            color: Colors.surfaceContainerHigh
            Text { anchors.centerIn: parent; text: "‹"; font.pixelSize: BarConfig.fsLg; color: Colors.colOnSurfaceVariant }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tabBar.rotate(-1) }
        }

        // 3 tab slots
        Row {
            anchors { left: prevBtn.right; right: nextBtn.left; leftMargin: BarConfig.sp(4); rightMargin: BarConfig.sp(4); verticalCenter: parent.verticalCenter }
            height: tabBar.height
            spacing: BarConfig.sp(2)

            Repeater {
                model: 3
                Item {
                    id: slotItem
                    required property int index
                    readonly property int tabIdx: (root._winStart + index) % tabBar._n
                    readonly property bool active: tabIdx === root.activeTab

                    width: tabBar._tabW
                    height: tabBar.height - BarConfig.sp(8)
                    clip: true

                    SequentialAnimation {
                        id: tabSlideAnim
                        running: false
                        PropertyAction  { target: slotItem; property: "_contentX"; value: -root._slideDir * tabBar._tabW * 0.5 }
                        NumberAnimation { target: slotItem; property: "_contentX"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                    }
                    property real _contentX: 0
                    onTabIdxChanged: if (root._slideDir !== 0) tabSlideAnim.restart()

                    Rectangle {
                        x: parent._contentX
                        width: parent.width; height: parent.height
                        radius: BarConfig.sp(8)
                        color: parent.active ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: root._tabs[parent.parent.tabIdx]
                            color: parent.parent.active ? Colors.primary : Colors.colOnSurfaceVariant
                            font.pixelSize: BarConfig.fsMd; font.weight: parent.parent.active ? Font.Bold : Font.Normal; font.letterSpacing: 0.8
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: tabBar.rotate(parent.index - 1)
                    }
                }
            }
        }

        // Next arrow
        Rectangle {
            id: nextBtn
            anchors { right: parent.right; rightMargin: BarConfig.sp(8); verticalCenter: parent.verticalCenter }
            width: tabBar._btnSz; height: tabBar._btnSz
            radius: BarConfig.sp(6)
            color: Colors.surfaceContainerHigh
            Text { anchors.centerIn: parent; text: "›"; font.pixelSize: BarConfig.fsLg; color: Colors.colOnSurfaceVariant }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tabBar.rotate(1) }
        }

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Colors.outlineVariant; opacity: 0.3 }
    }

    // ── Scrollable content ────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors { top: tabBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: BarConfig.sp(14) }
        contentWidth: width
        contentHeight: inner.implicitHeight + 24
        clip: true

        Column {
            id: inner
            width: flick.width - 32
            x: 16
            y: 12
            spacing: BarConfig.sp(12)

            property real _slideX: 0
            transform: Translate { x: inner._slideX }

            SequentialAnimation {
                id: contentSlideAnim
                PropertyAction  { target: inner; property: "_slideX"; value: root._slideDir * root.width * 0.12 }
                NumberAnimation { target: inner; property: "_slideX"; to: 0; duration: 200; easing.type: Easing.OutCubic }
            }

            // ── TAB 1: BAR ───────────────────────────────────────────────
            SLabel { visible: root.activeTab === 1; text: "LAYOUT" }

            SRow {
                visible: root.activeTab === 1
                label: "Style"
                Row {
                    spacing: BarConfig.sp(4)
                    Btn { lbl: "Hang";  active: BarConfig.fillMode === "hanging"; onPick: BarConfig.fillMode = "hanging" }
                    Btn { lbl: "Float"; active: BarConfig.fillMode === "pill";    onPick: BarConfig.fillMode = "pill" }
                }
            }

            SRow {
                visible: root.activeTab === 1
                label: "Auto-hide"
                Toggle { checked: BarConfig.autoHide; onToggled: (v) => BarConfig.autoHide = v }
            }

            SRow {
                visible: root.activeTab === 1 && BarConfig.fillMode !== "full"
                label: "Width"
                Row {
                    spacing: BarConfig.sp(8)
                    SimpleSlider {
                        minVal: 0.35; maxVal: 1.0
                        value: BarConfig.pillWidthPct
                        onMoved: (v) => BarConfig.pillWidthPct = Math.round(v * 100) / 100
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: Math.round(BarConfig.pillWidthPct * 100) + "%"
                        color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            SRow {
                visible: root.activeTab === 1
                label: "Opacity"
                Row {
                    spacing: BarConfig.sp(8)
                    SimpleSlider {
                        minVal: 0.4; maxVal: 1.0
                        value: BarConfig.barOpacity
                        onMoved: (v) => BarConfig.barOpacity = Math.round(v * 100) / 100
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: Math.round(BarConfig.barOpacity * 100) + "%"
                        color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            SRow {
                visible: root.activeTab === 1
                label: "Scale"
                Row {
                    spacing: BarConfig.sp(8)
                    SimpleSlider {
                        minVal: 0.5; maxVal: 2.0
                        value: BarConfig.uiScale
                        onMoved: (v) => BarConfig.uiScale = Math.round(v * 20) / 20
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: Math.round(BarConfig.uiScale * 100) + "%"
                        color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            HR { visible: root.activeTab === 1 }

            // ── TAB 2: WIDGETS ───────────────────────────────────────────
            SLabel { visible: root.activeTab === 2; text: "WIDGETS" }

            SRow { visible: root.activeTab === 2; label: "Workspaces";  Toggle { checked: BarConfig.showWorkspaces; onToggled: (v) => BarConfig.showWorkspaces = v } }
            SRow { visible: root.activeTab === 2; label: "MPRIS Player"; Toggle { checked: BarConfig.showMpris;    onToggled: (v) => BarConfig.showMpris = v } }
            SRow { visible: root.activeTab === 2; label: "Clock";        Toggle { checked: BarConfig.showClock;    onToggled: (v) => BarConfig.showClock = v } }
            SRow { visible: root.activeTab === 2; label: "System Tray";  Toggle { checked: BarConfig.showTray;     onToggled: (v) => BarConfig.showTray = v } }
            SRow { visible: root.activeTab === 2; label: "Volume";       Toggle { checked: BarConfig.showVolume;   onToggled: (v) => BarConfig.showVolume = v } }
            SRow { visible: root.activeTab === 2; label: "Network";      Toggle { checked: BarConfig.showNetwork;  onToggled: (v) => BarConfig.showNetwork = v } }
            SRow { visible: root.activeTab === 2; label: "CPU Usage";    Toggle { checked: BarConfig.showCpu;      onToggled: (v) => BarConfig.setCpu(v) } }
            SRow { visible: root.activeTab === 2; label: "Memory";       Toggle { checked: BarConfig.showMemory;   onToggled: (v) => BarConfig.setMemory(v) } }

            HR { visible: root.activeTab === 2 }

            SLabel { visible: root.activeTab === 2; text: "WIDGET ORDER (RIGHT)" }

            Column {
                visible: root.activeTab === 2
                width: parent.width
                Repeater {
                    model: BarConfig.rightWidgets
                    Item {
                        required property string modelData
                        required property int index
                        width: parent.width; height: BarConfig.sp(32)

                        Item {
                            anchors.fill: parent
                            Text {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                text: modelData; color: Colors.colOnSurface; font.pixelSize: BarConfig.fs
                                width: BarConfig.sp(120)
                            }
                            Row {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: BarConfig.sp(4)
                                Rectangle {
                                    width: BarConfig.sp(26); height: BarConfig.sp(26); radius: BarConfig.sp(6); color: Colors.surfaceContainerHigh
                                    Text { anchors.centerIn: parent; text: "▴"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (index <= 0) return
                                            const arr = [...BarConfig.rightWidgets]
                                            const tmp = arr[index - 1]; arr[index - 1] = arr[index]; arr[index] = tmp
                                            BarConfig.rightWidgets = arr
                                        }
                                    }
                                }
                                Rectangle {
                                    width: BarConfig.sp(26); height: BarConfig.sp(26); radius: BarConfig.sp(6); color: Colors.surfaceContainerHigh
                                    Text { anchors.centerIn: parent; text: "▾"; color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (index >= BarConfig.rightWidgets.length - 1) return
                                            const arr = [...BarConfig.rightWidgets]
                                            const tmp = arr[index + 1]; arr[index + 1] = arr[index]; arr[index] = tmp
                                            BarConfig.rightWidgets = arr
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HR { visible: root.activeTab === 2 }

            // ── TAB 3: NOTIFICATIONS ─────────────────────────────────────
            SLabel { visible: root.activeTab === 3; text: "TOAST POPUPS" }

            SRow {
                visible: root.activeTab === 3
                label: "Max popups"
                Row {
                    spacing: BarConfig.sp(8)
                    SimpleSlider {
                        minVal: 1; maxVal: 10
                        value: BarConfig.maxToastPopups
                        onMoved: (v) => BarConfig.maxToastPopups = Math.round(v)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: BarConfig.maxToastPopups
                        color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            HR { visible: root.activeTab === 3 }

            SLabel { visible: root.activeTab === 3; text: "DRAWER" }

            SRow {
                visible: root.activeTab === 3
                label: "History limit"
                Row {
                    spacing: BarConfig.sp(8)
                    SimpleSlider {
                        minVal: 5; maxVal: 100
                        value: BarConfig.maxDrawerNotifs
                        onMoved: (v) => BarConfig.maxDrawerNotifs = Math.round(v)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: BarConfig.maxDrawerNotifs
                        color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            HR { visible: root.activeTab === 3 }

            // ── TAB 0: APPEARANCE ────────────────────────────────────────
            SLabel { visible: root.activeTab === 0; text: "TRANSPARENCY" }

            SRow {
                visible: root.activeTab === 0
                label: "Opacity"
                Row {
                    spacing: BarConfig.sp(8)
                    SimpleSlider {
                        minVal: 0.4; maxVal: 1.0
                        value: BarConfig.barOpacity
                        onMoved: (v) => BarConfig.barOpacity = Math.round(v * 100) / 100
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: Math.round(BarConfig.barOpacity * 100) + "%"
                        color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            SLabel { visible: root.activeTab === 0; text: "BLUR STRENGTH" }

            SRow {
                visible: root.activeTab === 0
                label: "Blur"
                Row {
                    spacing: BarConfig.sp(8)
                    SimpleSlider {
                        id: blurSlider
                        minVal: 0; maxVal: 20
                        value: root.blurStrength
                        onMoved: (v) => {
                            root.blurStrength = Math.round(v)
                            blurProc.command = ["hyprctl", "keyword", "decoration:blur:size", String(Math.round(v))]
                            blurProc.running = true
                        }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: Math.round(root.blurStrength)
                        color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            HR { visible: root.activeTab === 0 }

            SLabel { visible: root.activeTab === 0; text: "ACCENT PRESETS" }

            Row {
                visible: root.activeTab === 0
                spacing: BarConfig.sp(8)
                Repeater {
                    model: BarConfig.tintPresets
                    Rectangle {
                        required property string modelData
                        required property int index
                        width: BarConfig.sp(24); height: BarConfig.sp(24); radius: BarConfig.sp(12)
                        color: modelData
                        border.color: BarConfig.tintIndex === index
                            ? (root._accentApplied ? "#22c55e" : "white")
                            : "transparent"
                        border.width: 2
                        Behavior on border.color { ColorAnimation { duration: 180 } }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { BarConfig.tintIndex = index; root._accentApplied = true; accentFlashTimer.restart() }
                        }
                    }
                }
            }

            Item {
                visible: root.activeTab === 0
                width: parent.width; height: BarConfig.sp(32)

                Rectangle {
                    id: hexBox
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: BarConfig.sp(108); height: BarConfig.sp(26); radius: BarConfig.sp(6)
                    color: Colors.surfaceContainerHigh
                    border.color: hexInput.activeFocus ? Colors.primary : Colors.outline; border.width: 1
                    TapHandler { onTapped: hexInput.forceActiveFocus() }
                    TextInput {
                        id: hexInput
                        anchors { fill: parent; leftMargin: BarConfig.sp(8); rightMargin: BarConfig.sp(8) }
                        verticalAlignment: TextInput.AlignVCenter
                        activeFocusOnTab: true
                        text: Colors.primary.toString().toUpperCase().substring(0, 7)
                        color: Colors.colOnSurface; font.pixelSize: BarConfig.fsMd; font.family: "monospace"
                        maximumLength: 7; selectByMouse: true; cursorVisible: activeFocus
                        Keys.onReturnPressed: applyHex()
                        function applyHex() {
                            const h = text.trim()
                            if (/^#[0-9A-Fa-f]{6}$/.test(h)) Colors.primary = Qt.color(h)
                        }
                    }
                }
                Rectangle {
                    anchors.left: hexBox.right; anchors.leftMargin: BarConfig.sp(6); anchors.verticalCenter: parent.verticalCenter
                    width: BarConfig.sp(26); height: BarConfig.sp(26); radius: BarConfig.sp(13)
                    color: { const h = hexInput.text.trim(); return /^#[0-9A-Fa-f]{6}$/.test(h) ? h : Colors.primary }
                    border.color: Colors.outline; border.width: 1
                }
                Rectangle {
                    id: applyBtn
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: BarConfig.sp(48); height: BarConfig.sp(26); radius: BarConfig.sp(13)
                    color: root._accentApplied ? "#22c55e" : Colors.primary
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Text { anchors.centerIn: parent; text: root._accentApplied ? "✓" : "Apply"; font.pixelSize: BarConfig.fsSm; color: Colors.colOnPrimary }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { hexInput.applyHex(); root._accentApplied = true; accentFlashTimer.restart() }
                    }
                }
            }

            HR { visible: root.activeTab === 0 }

            // ── TAB 4: KEYBINDS ─────────────────────────────────────────

            SLabel { visible: root.activeTab === 4; text: "OPEN" }

            Repeater {
                model: root.activeTab === 4 ? root._bindDefs : []
                delegate: Item {
                    id: bindRow
                    required property var modelData
                    required property int index
                    width: inner.width
                    height: BarConfig.sp(36)

                    readonly property string currentBind: root._getBind(bindRow.modelData.key)
                    readonly property bool isDefault: bindRow.currentBind === BarConfig._bindDefaults[bindRow.modelData.key]
                    readonly property bool hasConflict: root._hasConflict(bindRow.modelData.key, bindRow.currentBind)
                    readonly property bool isCapturing: root._capturingKey === bindRow.modelData.key
                    readonly property bool isGreen: root._greenKey === bindRow.modelData.key
                    readonly property bool isConflict: root._conflictKey === bindRow.modelData.key
                    readonly property bool isYellow: root._yellowKey === bindRow.modelData.key

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: bindRow.modelData.label
                        color: Colors.colOnSurface
                        font.pixelSize: BarConfig.fs
                    }

                    // Reset arrow — visible when not default
                    Text {
                        id: resetArrow
                        anchors.right: bindBtn.left
                        anchors.rightMargin: BarConfig.sp(8)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↺"
                        font.pixelSize: BarConfig.fsLg
                        color: Colors.primary
                        opacity: bindRow.isDefault ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            enabled: !bindRow.isDefault
                            onClicked: root._setBind(bindRow.modelData.key, BarConfig._bindDefaults[bindRow.modelData.key])
                        }
                    }

                    // Keybind button
                    Rectangle {
                        id: bindBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: BarConfig.sp(140)
                        height: BarConfig.sp(28)
                        radius: BarConfig.sp(6)
                        color: bindRow.isCapturing
                            ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.15)
                            : bindRow.isGreen
                                ? Qt.rgba(0.13, 0.77, 0.37, 0.15)
                                : bindRow.isYellow
                                    ? Qt.rgba(0.98, 0.75, 0.18, 0.12)
                                    : (bindRow.hasConflict || bindRow.isConflict)
                                        ? Qt.rgba(0.94, 0.27, 0.27, 0.12)
                                        : Colors.surfaceContainerHigh
                        border.width: 1
                        border.color: bindRow.isGreen
                            ? "#21c45d"
                            : bindRow.isYellow
                                ? "#f9be2e"
                                : (bindRow.hasConflict || bindRow.isConflict)
                                    ? "#ef4444"
                                    : bindRow.isCapturing
                                        ? Colors.primary
                                        : Colors.outline
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        Behavior on color        { ColorAnimation { duration: 120 } }

                        SequentialAnimation {
                            running: bindRow.isCapturing
                            loops: Animation.Infinite
                            NumberAnimation { target: bindBtn; property: "opacity"; to: 0.6; duration: 500; easing.type: Easing.InOutSine }
                            NumberAnimation { target: bindBtn; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.InOutSine }
                            onStopped: bindBtn.opacity = 1.0
                        }

                        Text {
                            anchors.centerIn: parent
                            text: {
                                if (bindRow.isCapturing) return root._captureDisplay || "Press keys…"
                                if (bindRow.isYellow)   return root._yellowMsg
                                if (bindRow.isConflict) return "Already bound"
                                const b = bindRow.currentBind
                                return b ? (root._displayStr(b) || "—") : "—"
                            }
                            color: bindRow.isCapturing    ? Colors.primary
                                 : bindRow.isGreen        ? "#21c45d"
                                 : bindRow.isYellow       ? "#f9be2e"
                                 : bindRow.isConflict     ? "#ef4444"
                                 : Colors.colOnSurface
                            font.pixelSize: BarConfig.fsSm
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: parent.width - BarConfig.sp(8)
                            horizontalAlignment: Text.AlignHCenter
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (bindRow.isCapturing) return
                                root._startCapture(bindRow.modelData.key)
                            }
                        }
                    }
                }
            }

            Item { height: BarConfig.sp(8); visible: root.activeTab === 4 }
            Item { height: BarConfig.sp(8) }
        }
    }

    // ── Key capture overlay ───────────────────────────────────────────────
    Timer {
        id: captureTimeout
        interval: parseInt(Quickshell.env("AETHERA_CAPTURE_TIMEOUT") || "3000")
        onTriggered: root._cancelCapture()
    }

    // Conflict check: run hyprctl binds -j before committing
    property string _pendingCommitKey: ""
    property string _pendingCommitBind: ""
    property string _conflictKey:  ""

    Process {
        id: hyprBindsProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector { id: hyprBindsOut }
        onExited: root._onHyprBindsResult()
    }

    Timer {
        id: conflictFlashTimer
        interval: parseInt(Quickshell.env("AETHERA_CAPTURE_CONFLICT_MS") || "2000")
        onTriggered: root._conflictKey = ""
    }

    Timer {
        id: addKeyTimer
        interval: 1500
        onTriggered: root._cancelCapture()
    }

    function _onHyprBindsResult() {
        const key  = _pendingCommitKey
        const bind = _pendingCommitBind
        _pendingCommitKey  = ""
        _pendingCommitBind = ""
        if (!key || !bind) return

        const parts   = bind.split("+")
        const trigKey = parts[parts.length - 1].toLowerCase()
        const mods    = parts.slice(0, parts.length - 1)
        let modmask   = 0
        if (mods.includes("SHIFT")) modmask |= 1
        if (mods.includes("CTRL"))  modmask |= 4
        if (mods.includes("ALT"))   modmask |= 8
        if (mods.includes("SUPER")) modmask |= 64

        try {
            const binds = JSON.parse(hyprBindsOut.text.trim())
            for (const b of binds) {
                if (b.modmask !== modmask) continue
                if (b.key.toLowerCase() !== trigKey) continue
                if (b.arg && b.arg.includes("qs ipc")) continue
                _conflictKey = key
                conflictFlashTimer.restart()
                return
            }
        } catch(e) {}

        _doCommit(key, bind)
    }

    Item {
        id: captureOverlay
        anchors.fill: parent
        visible: root._capturingKey !== ""

        Item {
            id: captureInput
            anchors.fill: parent
            focus: true

            Keys.onPressed: (e) => {
                e.accepted = true
                const k = e.key
                if (k === Qt.Key_Escape) { root._cancelCapture(); return }
                if (e.isAutoRepeat) return
                const modParts = root._modsFromEvent(e.modifiers, k)
                if (root._isModifierKey(k)) {
                    if (root._liveBind === "") captureTimeout.restart()
                    root._lastMods = e.modifiers
                    const hasAltGr = (e.modifiers & 0x40000000) || k === 16781571
                    const disp = modParts.join("+")
                    root._captureDisplay = hasAltGr && disp ? disp + " › …" : root._displayStr(disp)
                    return
                }
                const keyName = root._keyName(k, e.text)
                if (!keyName) {
                    root._captureDisplay = "Not supported"
                    unsupportedTimer.restart()
                    return
                }
                if (modParts.length === 0) {
                    const wk = root._capturingKey
                    root._cancelCapture()
                    root._yellowKey = wk; root._yellowMsg = "Add a modifier"
                    yellowFlashTimer.restart()
                    return
                }
                unsupportedTimer.stop()
                captureTimeout.stop()
                root._liveBind = modParts.concat([keyName]).join("+")
                root._captureDisplay = root._displayStr(root._liveBind)
            }

            Keys.onReleased: (e) => {
                e.accepted = true
                const k = e.key
                if (k === Qt.Key_Escape) return
                if (!root._isModifierKey(k)) {
                    if (root._liveBind !== "") root._commitCapture(root._liveBind)
                    return
                }
                root._lastMods = e.modifiers
                // Qt still reports the releasing key in e.modifiers, so filter it out
                const remaining = root._modsFromEvent(e.modifiers, 0).filter(m =>
                    !(k === 16777250 && m === "SUPER") &&
                    !(k === 16777249 && m === "CTRL")  &&
                    !(k === 16777251 && m === "ALT")   &&
                    !(k === 16777248 && m === "SHIFT")  &&
                    !(k === 16781571 && m === "AltGr")
                )
                if (remaining.length === 0) {
                    if (root._liveBind !== "") root._commitCapture(root._liveBind)
                    else {
                        const wk = root._capturingKey
                        root._cancelCapture()
                        root._yellowKey = wk; root._yellowMsg = "Add a key"
                        yellowFlashTimer.restart()
                    }
                } else {
                    root._captureDisplay = root._displayStr(remaining.join("+"))
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onWheel: (e) => { e.accepted = true }
            onPressed: (e) => {
                e.accepted = true
                captureInput.forceActiveFocus()
                if (e.button === 1 || e.button === 2) { root._cancelCapture(); return }
                captureTimeout.restart()
            }
        }

        onVisibleChanged: if (visible) captureInput.forceActiveFocus()
    }

    // ── Capture state ─────────────────────────────────────────────────────
    property string _capturingKey:        ""
    on_CapturingKeyChanged: BarConfig.capturingKey = _capturingKey
    property string _capturePrev:         ""
    property string _captureDisplay:      ""
    property string _liveBind:            ""
    property bool   _unsupportedFlash:    false
    property string _greenKey:  ""
    property string _yellowKey: ""
    property string _yellowMsg: ""

    Timer { id: yellowFlashTimer; interval: parseInt(Quickshell.env("AETHERA_CAPTURE_YELLOW_MS") || "1200"); onTriggered: root._yellowKey = "" }

    Timer {
        id: unsupportedTimer
        interval: 600
        onTriggered: {
            root._unsupportedFlash = false
            root._captureDisplay = root._displayStr(root._modsFromEvent(root._lastMods, 0).join("+"))
        }
    }
    property int _lastMods: 0

    Timer {
        id: greenFlashTimer
        interval: parseInt(Quickshell.env("AETHERA_CAPTURE_GREEN_MS") || "1200")
        onTriggered: root._greenKey = ""
    }

    readonly property var _bindDefs: [
        { key: "drawer",        label: "Sidebar" },
        { key: "launcher",      label: "App Launcher" },
        { key: "controlcenter", label: "Control Center" },
        { key: "power",         label: "Power Menu" },
        { key: "settings",      label: "Settings" },
        { key: "notifications", label: "Notifications" },
        { key: "wifi",          label: "WiFi Settings" },
        { key: "bluetooth",     label: "Bluetooth" },
        { key: "workspacemenu", label: "Workspace Menu" }
    ]

    function _getBind(key) {
        switch(key) {
            case "drawer":        return BarConfig.bindDrawer
            case "launcher":      return BarConfig.bindLauncher
            case "controlcenter": return BarConfig.bindControlCenter
            case "power":         return BarConfig.bindPower
            case "settings":      return BarConfig.bindSettings
            case "notifications": return BarConfig.bindNotifications
            case "wifi":          return BarConfig.bindWifi
            case "bluetooth":     return BarConfig.bindBluetooth
            case "workspacemenu": return BarConfig.bindWorkspaceMenu
        }
        return ""
    }

    function _setBind(key, value) {
        switch(key) {
            case "drawer":        BarConfig.bindDrawer        = value; break
            case "launcher":      BarConfig.bindLauncher      = value; break
            case "controlcenter": BarConfig.bindControlCenter = value; break
            case "power":         BarConfig.bindPower         = value; break
            case "settings":      BarConfig.bindSettings      = value; break
            case "notifications": BarConfig.bindNotifications = value; break
            case "wifi":          BarConfig.bindWifi          = value; break
            case "bluetooth":     BarConfig.bindBluetooth     = value; break
            case "workspacemenu": BarConfig.bindWorkspaceMenu = value; break
        }
    }

    function _hasConflict(key, bind) {
        if (!bind) return false
        const keys = ["drawer","launcher","controlcenter","power","settings"]
        for (const k of keys) {
            if (k !== key && _getBind(k) === bind) return true
        }
        return false
    }

    function _isModifierKey(k) {
        return (k >= 16777248 && k <= 16777263)
            || k === 16781571   // AltGr
    }

    function _modsFromEvent(mods, k) {
        const parts = []
        if ((mods & 0x10000000) || k === 16777250) parts.push("SUPER")
        if ((mods & 0x04000000) || k === 16777249) parts.push("CTRL")
        if ((mods & 0x08000000) || k === 16777251) parts.push("ALT")
        if ((mods & 0x02000000) || k === 16777248) parts.push("SHIFT")
        if ((mods & 0x40000000) || k === 16781571) parts.push("AltGr")
        return parts
    }

    function _keyName(k, text) {
        // A-Z (65-90) and 0-9 (48-57) by key code — reliable regardless of modifiers affecting text
        if (k >= 65 && k <= 90) return String.fromCharCode(k)
        if (k >= 48 && k <= 57) return String.fromCharCode(k)
        const names = {
            16777220: "Return",  16777221: "Return",
            16777217: "Tab",     16777219: "Backspace",
            16777223: "Delete",  16777222: "Insert",
            16777232: "Home",    16777233: "End",
            16777238: "Prior",   16777239: "Next",
            16777234: "Left",    16777236: "Right",
            16777235: "Up",      16777237: "Down",
            16908289: "Print",   16777224: "Pause",
            16777252: "Caps_Lock", 16777253: "Num_Lock",
            16777264: "F1",  16777265: "F2",  16777266: "F3",  16777267: "F4",
            16777268: "F5",  16777269: "F6",  16777270: "F7",  16777271: "F8",
            16777272: "F9",  16777273: "F10", 16777274: "F11", 16777275: "F12",
        }
        if (names[k]) return names[k]
        // Any printable char (including composed AltGr chars, unicode, symbols)
        if (text && text.trim().length > 0 && text.trim() === text) {
            const t = text.trim()
            // Only uppercase plain ASCII letters — leave everything else (é, œ, ø, £, 中, etc.) as-is
            return (t.length === 1 && t >= 'a' && t <= 'z') ? t.toUpperCase() : t
        }
        return ""
    }

    function _displayStr(bindStr) {
        if (!bindStr) return ""
        const friendly = { "mouse:274":"Middle Click", "mouse:275":"Back", "mouse:276":"Forward" }
        return bindStr.split("+").map(p => friendly[p] || p).join(" + ")
    }

    function _startCapture(key) {
        _capturePrev       = _getBind(key)
        _capturingKey      = key
        _captureDisplay    = ""
        _liveBind          = ""
        _unsupportedFlash  = false
        _lastMods          = 0
        if (_greenKey  === key) { _greenKey  = ""; greenFlashTimer.stop() }
        if (_yellowKey === key) { _yellowKey = ""; yellowFlashTimer.stop() }
        captureTimeout.restart()
    }

    function _cancelCapture() {
        captureTimeout.stop()
        unsupportedTimer.stop()
        addKeyTimer.stop()
        _capturingKey      = ""
        _captureDisplay    = ""
        _liveBind          = ""
        _unsupportedFlash  = false
        _lastMods          = 0
    }

    function _commitCapture(bindStr) {
        captureTimeout.stop()
        unsupportedTimer.stop()
        addKeyTimer.stop()
        const key = _capturingKey
        _capturingKey      = ""
        _captureDisplay    = ""
        _liveBind          = ""
        _unsupportedFlash  = false
        _lastMods          = 0
        if (!bindStr) return
        // Check for Hyprland conflicts before committing
        _pendingCommitKey  = key
        _pendingCommitBind = bindStr
        hyprBindsProc.running = true
    }

    function _doCommit(key, bindStr) {
        _setBind(key, bindStr)
        _greenKey = key
        greenFlashTimer.restart()
    }

    // Scrollbar
    Rectangle {
        visible: flick.contentHeight > flick.height
        anchors.right: parent.right; anchors.rightMargin: BarConfig.sp(4)
        readonly property real _r: BarConfig.sp(14)
        readonly property real _thumbH: flick.visibleArea.heightRatio * flick.height
        y: Math.max(flick.y, Math.min(flick.y + flick.height - _thumbH - _r,
                    flick.y + flick.visibleArea.yPosition * flick.height))
        width: BarConfig.sp(3); height: _thumbH
        radius: BarConfig.sp(2); color: Colors.outline; opacity: 0.6; z: 5
    }
}
