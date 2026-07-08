pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    property string mode:    ""     // "volume" | "brightness" | "wifi"
    property real   value:   0      // 0-1 for progress bar
    property string label:   ""     // text shown below icon
    property bool   visible: false

    Timer {
        id: hideTimer
        interval: 2000
        running:  false
        onTriggered: root.visible = false
    }

    function showVolume(v, muted) {
        mode    = "volume"
        value   = muted ? 0 : Math.min(v, 1.0)
        label   = muted ? "Muted" : Math.round(v * 100) + "%"
        visible = true
        hideTimer.restart()
    }

    function showBrightness(v) {
        mode    = "brightness"
        value   = Math.max(0, Math.min(1, v))
        label   = Math.round(v * 100) + "%"
        visible = true
        hideTimer.restart()
    }

    function showWifi(ssid) {
        mode    = "wifi"
        value   = ssid ? 1 : 0
        label   = ssid || "Disconnected"
        visible = true
        hideTimer.restart()
    }
}
