pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Item {
    id: root
    clip: true

    component SLabel: Text {
        color: Colors.primary; font.pixelSize: 9
        font.weight: Font.Medium; font.letterSpacing: 1; opacity: 0.8
    }
    component HR: Rectangle {
        width: parent?.width ?? 400; height: 1; color: Colors.outlineVariant; opacity: 0.5
    }
    component SRow: Item {
        id: sr; required property string label; default property alias children: srR.data
        width: parent?.width ?? 400; implicitHeight: 36
        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: sr.label; color: Colors.colOnSurface; font.pixelSize: 12 }
        Item { id: srR; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
               implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
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

            SLabel { text: "WIDGET VISIBILITY" }

            SRow { label: "Workspaces"; Toggle { checked: BarConfig.showWorkspaces; onToggled: (v) => BarConfig.showWorkspaces = v } }
            SRow { label: "MPRIS Player"; Toggle { checked: BarConfig.showMpris; onToggled: (v) => BarConfig.showMpris = v } }
            SRow { label: "Clock"; Toggle { checked: BarConfig.showClock; onToggled: (v) => BarConfig.showClock = v } }
            SRow { label: "System Tray"; Toggle { checked: BarConfig.showTray; onToggled: (v) => BarConfig.showTray = v } }
            SRow { label: "Volume"; Toggle { checked: BarConfig.showVolume; onToggled: (v) => BarConfig.showVolume = v } }
            SRow { label: "Network"; Toggle { checked: BarConfig.showNetwork; onToggled: (v) => BarConfig.showNetwork = v } }
            SRow { label: "CPU Usage"; Toggle { checked: BarConfig.showCpu; onToggled: (v) => BarConfig.setCpu(v) } }
            SRow { label: "Memory"; Toggle { checked: BarConfig.showMemory; onToggled: (v) => BarConfig.setMemory(v) } }

            HR {}
            SLabel { text: "WIDGET ORDER (RIGHT SECTION)" }

            Column {
                width: parent.width; spacing: 2

                Repeater {
                    model: BarConfig.rightWidgets
                    Item {
                        required property string modelData
                        required property int index
                        width: parent?.width ?? 400; height: 36

                        Rectangle {
                            anchors { fill: parent; topMargin: 2; bottomMargin: 2 }
                            radius: 8; color: Colors.surfaceContainerHigh

                            Row {
                                anchors { left: parent.left; right: parent.right
                                          leftMargin: 12; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                spacing: 0

                                Text {
                                    text: modelData; color: Colors.colOnSurface; font.pixelSize: 12
                                    width: parent.width - 68
                                }

                                Row {
                                    spacing: 4
                                    Rectangle {
                                        width: 26; height: 26; radius: 6; color: Colors.surface
                                        Text { anchors.centerIn: parent; text: "▴"
                                               color: Colors.colOnSurfaceVariant; font.pixelSize: 11 }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const idx = index
                                                if (idx <= 0) return
                                                const arr = [...BarConfig.rightWidgets]
                                                const tmp = arr[idx - 1]; arr[idx - 1] = arr[idx]; arr[idx] = tmp
                                                BarConfig.rightWidgets = arr
                                            }
                                        }
                                    }
                                    Rectangle {
                                        width: 26; height: 26; radius: 6; color: Colors.surface
                                        Text { anchors.centerIn: parent; text: "▾"
                                               color: Colors.colOnSurfaceVariant; font.pixelSize: 11 }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const idx = index
                                                if (idx >= BarConfig.rightWidgets.length - 1) return
                                                const arr = [...BarConfig.rightWidgets]
                                                const tmp = arr[idx + 1]; arr[idx + 1] = arr[idx]; arr[idx] = tmp
                                                BarConfig.rightWidgets = arr
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item { height: 8 }
        }
    }
}
