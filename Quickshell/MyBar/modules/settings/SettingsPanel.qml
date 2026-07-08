pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"

PanelWindow {
    id: settingsWin

    color: "transparent"
    WlrLayershell.namespace: "quickshell:mybar-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { top: true; bottom: true; left: true; right: true }

    visible: ShellState.settingsOpen

    // Selected sidebar section index
    property int selectedSection: 0

    readonly property var sectionSources: [
        "SettingsGeneral.qml",
        "SettingsAppearance.qml",
        "SettingsBar.qml",
        "SettingsWidgets.qml",
        "SettingsNotifications.qml",
        "SettingsNetwork.qml",
        "SettingsBluetooth.qml",
        "SettingsAudio.qml",
        "SettingsDisplay.qml",
        "SettingsSystem.qml"
    ]

    // Nerd Font glyphs for each section
    readonly property var sectionIcons: [
        "", "", "",
        "", "", "",
        "", "", "", ""
    ]
    readonly property var sectionLabels: [
        "General", "Appearance", "Bar",
        "Widgets", "Notifications", "Network",
        "Bluetooth", "Audio", "Display", "System"
    ]

    // Transparent click-catcher — NO dim overlay ever
    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShellState.closeSettings()
        MouseArea { anchors.fill: parent; onClicked: ShellState.closeSettings() }
    }

    // Main panel
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 900)
        height: Math.min(parent.height - 48, 620)
        radius: 20
        color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, 0.97)
        border.color: Colors.popupBorder
        border.width: 1
        clip: true

        // Enter animation
        scale: settingsWin.visible ? 1.0 : 0.92
        opacity: settingsWin.visible ? 1.0 : 0.0
        Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // Header
        Item {
            id: panelHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 52

            Text {
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                text: "Settings"
                color: Colors.colOnSurface
                font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Text {
                anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                text: "✕"
                color: Colors.colOnSurfaceVariant; font.pixelSize: 14
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: ShellState.closeSettings()
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1
                color: Colors.popupBorder; opacity: 0.6
            }
        }

        // Body: sidebar + content
        Row {
            anchors { top: panelHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }

            // Sidebar
            Rectangle {
                width: 196; height: parent.height
                color: Qt.rgba(Colors.surfaceContainer.r, Colors.surfaceContainer.g, Colors.surfaceContainer.b, 0.9)

                Flickable {
                    anchors { fill: parent; topMargin: 8; bottomMargin: 8 }
                    contentWidth: width
                    contentHeight: sideCol.implicitHeight
                    clip: true

                    Column {
                        id: sideCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: settingsWin.sectionLabels.length
                            SidebarItem {
                                required property int index
                                sectionIndex: index
                                icon: settingsWin.sectionIcons[index]
                                label: settingsWin.sectionLabels[index]
                                active: settingsWin.selectedSection === index
                                onSelected: settingsWin.selectedSection = index
                            }
                        }
                    }
                }
            }

            // Divider
            Rectangle { width: 1; height: parent.height; color: Colors.popupBorder; opacity: 0.7 }

            // Content area
            Item {
                width: parent.width - 197; height: parent.height

                Loader {
                    anchors.fill: parent
                    source: settingsWin.sectionSources[settingsWin.selectedSection]
                }
            }
        }
    }
}
