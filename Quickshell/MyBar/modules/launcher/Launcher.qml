pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../config"
import "../../services"

// Add to hyprland.conf: bind = SUPER, Space, exec, qs-ipc toggle-launcher

PanelWindow {
    id: launcherWin
    color: "transparent"

    WlrLayershell.namespace: "quickshell:mybar-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        left:   false
        right:  false
        top:    false
        bottom: false
    }

    exclusiveZone: -1

    implicitWidth:  launcherWin.screen ? launcherWin.screen.width  : BarConfig.sp(1920)
    implicitHeight: launcherWin.screen ? launcherWin.screen.height : BarConfig.sp(1080)

    visible: ShellState.launcherOpen

    // ── Backdrop ─────────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.closeLauncher()
    }

    // ── App data ──────────────────────────────────────────────────────────
    property var allApps: []
    property var filteredApps: []
    property int selectedIndex: 0
    property string searchText: ""

    onSearchTextChanged: {
        const q = launcherWin.searchText.toLowerCase().trim()
        if (q === "") {
            launcherWin.filteredApps = launcherWin.allApps.slice(0, 60)
        } else {
            launcherWin.filteredApps = launcherWin.allApps.filter(a =>
                a.name.toLowerCase().includes(q)
            ).slice(0, 60)
        }
        launcherWin.selectedIndex = 0
    }

    function launch(execStr) {
        if (!execStr) return
        const clean = execStr.replace(/%[uUfFdDnNickvm]/g, "").trim()
        // Redirect the launched app's stdout/stderr to /dev/null explicitly:
        // this wrapper bash exits almost instantly (the real command is
        // backgrounded), which closes the pipe it shares with the launched
        // app — anything the app later tries to print (e.g. kitty reporting
        // a config error) gets EPIPE/"Broken pipe" instead of just working.
        launchProc.command = ["bash", "-c", clean + " >/dev/null 2>&1 &"]
        launchProc.running = true
        ShellState.closeLauncher()
    }

    Process {
        id: launchProc
        command: ["bash", "-c", "true"]
    }

    // Pre-load at startup so first open is instant
    Component.onCompleted: reloadTimer.start()

    Process {
        id: desktopProc
        command: ["mybar-appscanner"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.length > 0)
                const apps = []
                for (const line of lines) {
                    const tab = line.indexOf("\t")
                    if (tab < 0) continue
                    const name = line.substring(0, tab).trim()
                    const exec = line.substring(tab + 1).trim()
                    if (name && exec) apps.push({ name: name, exec: exec })
                }
                launcherWin.allApps = apps
                launcherWin.filteredApps = apps.slice(0, 60)
            }
        }
    }

    // Open/close animation state
    property real _panelOpacity: 0
    property real _panelScale:   0.95

    onVisibleChanged: {
        if (visible) {
            searchBox.text = ""
            launcherWin.searchText = ""
            launcherWin.selectedIndex = 0
            Qt.callLater(() => { searchBox.forceActiveFocus() })
            // Reset then animate in
            launcherWin._panelOpacity = 0
            launcherWin._panelScale   = 0.95
            panelInAnim.restart()
            // Show cached list immediately; always re-scan in background
            if (launcherWin.allApps.length > 0)
                launcherWin.filteredApps = launcherWin.allApps.slice(0, 60)
            reloadTimer.start()
        } else {
            panelInAnim.stop()
        }
    }

    // Defer start so any in-progress run finishes before we re-trigger
    Timer {
        id: reloadTimer
        interval: 50
        onTriggered: {
            if (!desktopProc.running) desktopProc.running = true
        }
    }

    ParallelAnimation {
        id: panelInAnim
        NumberAnimation { target: launcherWin; property: "_panelOpacity"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: launcherWin; property: "_panelScale";   to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    // ── Panel ─────────────────────────────────────────────────────────────
    Rectangle {
        id: panel
        width:  BarConfig.sp(440)
        height: BarConfig.sp(560)
        radius: BarConfig.sp(16)
        // Consistent with all other popups/drawer per CLUES.md
        color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)
        border.color: Colors.popupBorder
        border.width: 1
        clip: true

        x: (launcherWin.width  - width)  / 2
        y: (launcherWin.height - height) / 2

        opacity:         launcherWin._panelOpacity
        scale:           launcherWin._panelScale
        transformOrigin: Item.Center

        layer.enabled: true

        MouseArea { anchors.fill: parent; onClicked: {} }

        Keys.onEscapePressed: ShellState.closeLauncher()
        Keys.onUpPressed: {
            if (launcherWin.selectedIndex > 0)
                launcherWin.selectedIndex--
        }
        Keys.onDownPressed: {
            if (launcherWin.selectedIndex < launcherWin.filteredApps.length - 1)
                launcherWin.selectedIndex++
        }
        Keys.onReturnPressed: {
            const app = launcherWin.filteredApps[launcherWin.selectedIndex]
            if (app) launcherWin.launch(app.exec)
        }

        // ── Search bar ────────────────────────────────────────────────────
        Rectangle {
            id: searchRow
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: BarConfig.sp(14) }
            height: BarConfig.sp(44)
            radius: BarConfig.sp(10)
            color: Colors.surfaceContainerHigh
            border.color: searchBox.activeFocus ? Colors.primary : Colors.popupBorder
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 150 } }

            Row {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: BarConfig.sp(12); rightMargin: BarConfig.sp(12) }
                spacing: BarConfig.sp(8)

                Text {
                    text: ""
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: BarConfig.fsLg
                    color: Colors.colOnSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                }

                TextInput {
                    id: searchBox
                    width: parent.width - 30
                    color: Colors.colOnSurface
                    font.pixelSize: BarConfig.fsLg
                    selectByMouse: true
                    cursorVisible: activeFocus
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.fill: parent
                        text:    "Search applications..."
                        color:   Colors.colOnSurfaceVariant
                        font:    searchBox.font
                        visible: searchBox.text.length === 0
                        opacity: 0.5
                    }

                    onTextChanged: launcherWin.searchText = text

                    Keys.onEscapePressed: ShellState.closeLauncher()
                    Keys.onUpPressed: {
                        if (launcherWin.selectedIndex > 0)
                            launcherWin.selectedIndex--
                    }
                    Keys.onDownPressed: {
                        if (launcherWin.selectedIndex < launcherWin.filteredApps.length - 1)
                            launcherWin.selectedIndex++
                    }
                    Keys.onReturnPressed: {
                        const app = launcherWin.filteredApps[launcherWin.selectedIndex]
                        if (app) launcherWin.launch(app.exec)
                    }
                }
            }
        }

        // ── Divider ───────────────────────────────────────────────────────
        Rectangle {
            id: divider
            anchors { top: searchRow.bottom; left: parent.left; right: parent.right; topMargin: BarConfig.sp(10) }
            height: 1
            color: Colors.popupBorder
            opacity: 0.5
        }

        // ── App list ──────────────────────────────────────────────────────
        Item {
            id: appListArea
            anchors {
                top:    divider.bottom
                left:   parent.left
                right:  parent.right
                bottom: parent.bottom
                topMargin:    BarConfig.sp(4)
                bottomMargin: BarConfig.sp(14)
            }

            Flickable {
                id: appFlick
                anchors { fill: parent; bottomMargin: BarConfig.sp(14) }
                contentWidth:  width
                contentHeight: appList.implicitHeight
                clip: true

                Connections {
                    target: launcherWin
                    function onSelectedIndexChanged() {
                        const itemH = BarConfig.sp(52)
                        const y = launcherWin.selectedIndex * itemH
                        if (y < appFlick.contentY) {
                            appFlick.contentY = y
                        } else if (y + itemH > appFlick.contentY + appFlick.height) {
                            appFlick.contentY = y + itemH - appFlick.height
                        }
                    }
                }

                Column {
                    id: appList
                    width: appFlick.width

                    Repeater {
                        model: launcherWin.filteredApps
                        delegate: Item {
                            id: appRow
                            required property var modelData
                            required property int index

                            width:  appFlick.width
                            height: BarConfig.sp(52)

                            property bool isSelected: index === launcherWin.selectedIndex
                            property bool isHovered:  rowHover.hovered

                            opacity: 0
                            Component.onCompleted: {
                                itemFadeTimer.interval = Math.min(appRow.index * 16, 100)
                                itemFadeTimer.restart()
                            }
                            Timer   { id: itemFadeTimer; onTriggered: itemFadeAnim.start() }
                            NumberAnimation { id: itemFadeAnim; target: appRow; property: "opacity"; from: 0; to: 1; duration: 130; easing.type: Easing.OutCubic }

                            Rectangle {
                                anchors { fill: parent; leftMargin: BarConfig.sp(8); rightMargin: BarConfig.sp(8); topMargin: BarConfig.sp(2); bottomMargin: BarConfig.sp(2) }
                                radius: BarConfig.sp(10)
                                color: {
                                    if (appRow.isSelected) return Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.18)
                                    if (appRow.isHovered)  return Colors.surfaceContainerHigh
                                    return "transparent"
                                }
                                Behavior on color { ColorAnimation { duration: 100 } }

                                Row {
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: BarConfig.sp(12); rightMargin: BarConfig.sp(12) }
                                    spacing: BarConfig.sp(12)

                                    Rectangle {
                                        width: BarConfig.sp(32); height: BarConfig.sp(32); radius: BarConfig.sp(8)
                                        property int _h: (appRow.modelData.name.charCodeAt(0) + (appRow.modelData.name.charCodeAt(1) || 0)) % 4
                                        color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.10 + _h * 0.04)
                                        border.color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.20 + _h * 0.05)
                                        border.width: 1
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: appRow.modelData.name.charAt(0).toUpperCase()
                                            font.pixelSize: BarConfig.fsLg; font.weight: Font.DemiBold
                                            color: Colors.primary
                                        }
                                    }

                                    Text {
                                        text:  appRow.modelData.name
                                        color: Colors.colOnSurface
                                        font.pixelSize: BarConfig.fsMd
                                        font.weight:    appRow.isSelected ? Font.Medium : Font.Normal
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        width: parent.width - BarConfig.sp(56)
                                    }
                                }
                            }

                            HoverHandler { id: rowHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: launcherWin.launch(appRow.modelData.exec)
                                onContainsMouseChanged: {
                                    if (containsMouse) launcherWin.selectedIndex = appRow.index
                                }
                            }
                        }
                    }
                }
            }

            // Scrollbar — sibling of Flickable per CLUES.md
            Rectangle {
                readonly property real _r: BarConfig.sp(14)
                readonly property real _thumbH: appFlick.visibleArea.heightRatio * appFlick.height
                visible: appFlick.contentHeight > appFlick.height
                anchors.right: parent.right
                anchors.rightMargin: BarConfig.sp(3)
                y: Math.max(appFlick.y, Math.min(appFlick.y + appFlick.height - _thumbH - _r,
                            appFlick.y + appFlick.visibleArea.yPosition * appFlick.height))
                width: BarConfig.sp(3)
                height: _thumbH
                radius: BarConfig.sp(2)
                color: Colors.outline
                opacity: 0.5
                z: 5
            }
        }
    }
}
