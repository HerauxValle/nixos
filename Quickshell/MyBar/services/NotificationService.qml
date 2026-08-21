pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property var notifications: []   // [{id, app, summary, body, actions, timestamp}]
    property int unreadCount: 0
    signal received(var notif)

    function dismiss(nid) {
        const idx = notifications.findIndex(n => n.id === nid)
        if (idx < 0) return
        const copy = notifications.slice()
        copy.splice(idx, 1)
        notifications = copy
        if (unreadCount > 0) unreadCount--
    }

    function dismissAll() {
        notifications = []
        unreadCount   = 0
    }

    function _handleLine(line: string) {
        if (!line || line[0] !== "{") return
        let obj
        try { obj = JSON.parse(line) } catch(e) { return }

        if (obj.type === "notify") {
            const notif = {
                id:        obj.id       ?? 0,
                app:       obj.app      ?? "Unknown",
                summary:   obj.summary  ?? "",
                body:      obj.body     ?? "",
                actions:   obj.actions  ?? [],
                timestamp: new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
            }
            const copy = [notif].concat(root.notifications)
            if (copy.length > BarConfig.maxDrawerNotifs) copy.splice(BarConfig.maxDrawerNotifs)
            root.notifications = copy
            root.unreadCount++
            root.received(notif)
        } else if (obj.type === "close") {
            root.dismiss(obj.id ?? 0)
        }
    }

    Process {
        id: _server
        command: ["mybar-notifserver"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root._handleLine(line)
        }
    }
}
