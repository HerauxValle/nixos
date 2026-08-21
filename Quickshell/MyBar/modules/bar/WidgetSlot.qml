import QtQuick
import "../../config"

Item {
    id: slot
    required property string widgetId
    property string barScreenName: ""

    implicitWidth:  inner.item ? inner.item.implicitWidth  : 0
    implicitHeight: inner.item ? inner.item.implicitHeight : 22
    visible: isVisible
    width:   isVisible ? implicitWidth : 0

    readonly property bool isVisible: {
        switch(slot.widgetId) {
            case "workspaces": return BarConfig.showWorkspaces
            case "mpris":      return BarConfig.showMpris
            case "clock":      return BarConfig.showClock
            case "tray":       return BarConfig.showTray
            case "cpu":        return BarConfig.showCpu
            case "memory":     return BarConfig.showMemory
            case "network":    return BarConfig.showNetwork
            case "volume":     return BarConfig.showVolume
            default:           return true
        }
    }

    Loader {
        id: inner
        active: slot.isVisible
        function reload() {
            const map = {
                "workspaces":   "../workspaces/Workspaces.qml",
                "mpris":        "../widgets/Mpris.qml",
                "clock":        "../clock/Clock.qml",
                "activewindow": "../widgets/ActiveWindow.qml",
                "tray":         "../systray/SystemTray.qml",
                "network":      "../widgets/NetworkWidget.qml",
                "volume":       "../widgets/VolumeWidget.qml",
                "cpu":          "../widgets/CpuWidget.qml",
                "memory":       "../widgets/MemoryWidget.qml",
            }
            const src = map[slot.widgetId] || ""
            if (!src) return
            if (slot.widgetId === "volume") {
                setSource(src, { barScreenName: slot.barScreenName })
            } else {
                source = src
            }
        }
        Component.onCompleted: reload()
    }
}
