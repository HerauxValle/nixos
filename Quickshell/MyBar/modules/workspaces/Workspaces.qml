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

    function updateOccupied() {
        wsOccupied = Array.from({length: 10}, (_, i) =>
            Hyprland.workspaces.values.some(ws => ws.id === i + 1)
        )
    }

    Component.onCompleted: updateOccupied()

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { root.updateOccupied() }
    }

    implicitWidth: wsRow.implicitWidth
    implicitHeight: wsRow.implicitHeight

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            Hyprland.dispatch(event.angleDelta.y < 0
                ? "workspace r+1" : "workspace r-1")
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

                readonly property int  wsId:    index + 1
                readonly property bool active:   wsId === root.activeWsId
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
                    text: String(wsItem.wsId).padStart(2, '0')
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
                            Qt.callLater(function() { BarConfig.togglePopup("workspacemenu", QsWindow.window?.screen?.name ?? "") })
                        } else {
                            Hyprland.dispatch("workspace " + wsItem.wsId)
                        }
                    }
                }
            }
        }
    }
}
