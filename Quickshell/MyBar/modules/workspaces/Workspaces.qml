pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../config"

Item {
    id: root

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(QsWindow.window?.screen)
    readonly property int activeWsId: monitor?.activeWorkspace?.id ?? 1

    property var wsOccupied: []
    // Dynamic count: show up to highest existing workspace ID + 1 (for creating new)
    readonly property int wsCount: {
        const vals = Hyprland.workspaces.values
        if (vals.length === 0) return Math.max(1, activeWsId)
        const maxId = Math.max(...vals.map(w => w.id))
        return Math.max(maxId, activeWsId, 1)
    }

    // Displayed workspace numbers always read 1..wsCount in natural order;
    // when BarConfig.invertWorkspaceIds is on, this maps that displayed
    // number onto the reversed raw Hyprland workspace ID instead (a
    // reflection is its own inverse, so the same function converts either
    // direction). Hyprland's workspaces slide animation is fixed to raw ID
    // comparison with no config override (confirmed: hyprwm/Hyprland
    // discussion #3828), so this is what actually flips its direction while
    // keeping what you see on the bar unchanged.
    function reflect(n) {
        return BarConfig.invertWorkspaceIds ? (root.wsCount + 1 - n) : n
    }

    function updateOccupied() {
        wsOccupied = Array.from({length: 10}, (_, i) =>
            Hyprland.workspaces.values.some(ws => ws.id === root.reflect(i + 1))
        )
    }

    Component.onCompleted: updateOccupied()

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { root.updateOccupied() }
    }
    Connections {
        target: BarConfig
        function onInvertWorkspaceIdsChanged() { root.updateOccupied() }
    }

    implicitWidth: wsRow.implicitWidth
    implicitHeight: wsRow.implicitHeight

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            const down = event.angleDelta.y < 0
            const rel = BarConfig.invertWorkspaceIds
                ? (down ? "r-1" : "r+1")
                : (down ? "r+1" : "r-1")
            // Plain "workspace <arg>" dispatch strings error on this Hyprland
            // build -- it parses every dispatch as a Lua expression
            // unconditionally (confirmed live: even a plain "workspace 5"
            // fails with "hl.dispatch(workspace 5)) ')' expected"), so this
            // needs the full hl.dsp.* Lua call form instead.
            Hyprland.dispatch("hl.dsp.focus({ workspace = '" + rel + "' })")
        }
    }

    Row {
        id: wsRow
        spacing: 6

        Repeater {
            model: root.wsCount

            delegate: Item {
                id: wsItem
                required property int index

                readonly property int  displayId: index + 1               // always shown in natural order
                readonly property int  wsId:      root.reflect(displayId)  // raw Hyprland ID actually dispatched to
                readonly property bool active:    wsId === root.activeWsId
                readonly property bool occupied: root.wsOccupied.length > index
                                                  && root.wsOccupied[index]

                implicitWidth:  wsLabel.implicitWidth + 8
                implicitHeight: wsLabel.implicitHeight + 4

                // Active workspace background
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Colors.primary
                    opacity: wsItem.active ? 0.30 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                Text {
                    id: wsLabel
                    anchors.centerIn: parent
                    text: String(wsItem.displayId).padStart(2, '0')
                    font.pixelSize: BarConfig.barFontSize - 1
                    font.family: "JetBrains Mono, monospace"
                    font.weight: wsItem.active ? Font.Medium : Font.Normal

                    color: wsItem.active   ? Colors.primary
                         : wsItem.occupied ? Colors.colOnSurface
                         :                   Colors.colOnSurfaceVariant

                    opacity: wsItem.active   ? 1.0
                           : wsItem.occupied ? 0.70
                           :                   0.35

                    Behavior on color   { ColorAnimation  { duration: 160 } }
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (event) => {
                        if (event.button === Qt.RightButton) {
                            BarConfig.ctxWorkspaceId = wsItem.wsId
                            BarConfig.ctxWorkspaceDisplay = wsItem.displayId
                            Qt.callLater(function() { BarConfig.togglePopup("workspacemenu", QsWindow.window?.screen?.name ?? "") })
                        } else {
                            Hyprland.dispatch("hl.dsp.focus({ workspace = '" + wsItem.wsId + "' })")
                        }
                    }
                }
            }
        }
    }
}
