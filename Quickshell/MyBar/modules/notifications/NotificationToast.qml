pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../config"
import "../../services"

Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: toastWin
            required property ShellScreen modelData
            screen: modelData

            readonly property bool _isFocused: Hyprland.focusedMonitor?.name === toastWin.screen.name

            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:mybar-toast"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors.top:   true
            anchors.right: true
            exclusiveZone: 0

            readonly property int _tw:  BarConfig.sp(328)
            readonly property int _th:  BarConfig.sp(72)
            readonly property int _gap: BarConfig.sp(8)
            readonly property int _r:   BarConfig.sp(12)
            readonly property int _ph:  BarConfig.sp(4)
            readonly property color _bg: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, BarConfig.barOpacity)
            readonly property int _max: BarConfig.maxToastPopups

            implicitWidth:  _tw + _gap
            implicitHeight: BarConfig.barHeight + _gap + (_th + _gap) * _max

            mask: Region { item: maskArea }
            Item {
                id: maskArea
                x: 0; y: BarConfig.barHeight + toastWin._gap
                width:  toastWin._isFocused && toasts.count > 0 ? toastWin._tw : 0
                height: toastWin._isFocused && toasts.count > 0
                        ? toasts.count * (toastWin._th + toastWin._gap)
                        : 0
            }

            property bool _ready: false
            Timer { interval: 300; running: true; onTriggered: toastWin._ready = true }

            // uid counter — each entry gets a unique id so timers are stable across shifts
            property int _uidCounter: 0

            // ListModel entries: { uid, app, summary, body }
            // Newest appended at the END (bottom). Oldest at index 0 (top).
            ListModel { id: toasts }

            // Map uid → Timer (keyed by uid, immune to index shifts)
            property var _timers: ({})

            // Incoming queue — all notifs go here first; processed one eviction at a time
            property var _queue: []
            property bool _evicting: false

            function _addNotif(notif) {
                if (!_isFocused) return
                _queue = [..._queue, { app: notif.app, summary: notif.summary, body: notif.body }]
                _processQueue()
            }

            function _processQueue() {
                if (_evicting) return
                while (_queue.length > 0) {
                    if (toasts.count < _max) {
                        const n = _queue.shift(); _queue = _queue
                        _append(n)
                    } else {
                        // Need to evict first — do one eviction then stop; resume after it completes
                        _evicting = true
                        const uid = toasts.get(0).uid
                        _evictingUid = uid
                        _removeTimer.targetUid = uid
                        _removeTimer.restart()
                        return
                    }
                }
            }

            function _append(notif) {
                const uid = ++_uidCounter
                toasts.append({ uid: uid, app: notif.app, summary: notif.summary, body: notif.body })
                _startTimer(uid)
            }

            function _startTimer(uid) {
                if (_timers[uid]) _timers[uid].destroy()
                const t = Qt.createQmlObject('import QtQuick; Timer { interval: 4000; running: true }', toastWin)
                t.triggered.connect(function() { _dismissByUid(uid) })
                _timers[uid] = t
            }

            function _dismissByUid(uid) {
                if (_indexOfUid(uid) < 0) return
                if (_evicting) {
                    // defer: push back as re-eviction after current one settles
                    _queue = [{ _dismissUid: uid }, ..._queue]
                    return
                }
                _evicting = true
                _evictingUid = uid
                _removeTimer.targetUid = uid
                _removeTimer.restart()
            }

            function _indexOfUid(uid) {
                for (let i = 0; i < toasts.count; i++)
                    if (toasts.get(i).uid === uid) return i
                return -1
            }

            // Which uid is currently sliding out (-1 = none)
            property int _evictingUid: -1

            Timer {
                id: _removeTimer
                interval: 260
                property int targetUid: -1
                onTriggered: {
                    const uid = targetUid
                    const idx = toastWin._indexOfUid(uid)
                    if (idx >= 0) toasts.remove(idx, 1)
                    if (toastWin._timers[uid]) {
                        toastWin._timers[uid].destroy()
                        delete toastWin._timers[uid]
                    }
                    toastWin._evictingUid = -1
                    toastWin._evicting = false
                    // Check if next queued item is a deferred dismiss
                    if (toastWin._queue.length > 0 && toastWin._queue[0]._dismissUid !== undefined) {
                        const duid = toastWin._queue.shift()._dismissUid
                        toastWin._queue = toastWin._queue
                        toastWin._dismissByUid(duid)
                    } else {
                        toastWin._processQueue()
                    }
                }
            }

            Connections {
                target: NotificationService
                function onReceived(notif) { toastWin._addNotif(notif) }
            }

            Repeater {
                model: toasts

                delegate: Rectangle {
                    id: toastDelegate
                    required property int    index
                    required property int    uid
                    required property string app
                    required property string summary
                    required property string body

                    width: toastWin._tw
                    height: toastWin._th

                    // y animates when index changes (items move up after eviction)
                    y: BarConfig.barHeight + toastWin._gap + index * (toastWin._th + toastWin._gap)
                    Behavior on y { enabled: toastWin._ready; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                    // x: start off-screen, animate in; animate out when evicted
                    property bool _spawned: false
                    x: (_spawned && toastWin._evictingUid !== uid) ? 0 : toastWin.implicitWidth
                    Behavior on x { enabled: toastWin._ready; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Component.onCompleted: Qt.callLater(function() { toastDelegate._spawned = true })

                    radius: toastWin._r; color: toastWin._bg; border.color: Colors.popupBorder; border.width: 1

                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleNotifications() }

                    Text {
                        id: bell
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: BarConfig.sp(14) }
                        text: ""; font.family: "Symbols Nerd Font Mono"; font.pixelSize: BarConfig.sp(20); color: Colors.primary
                    }
                    Column {
                        anchors { left: bell.right; right: parent.right; verticalCenter: parent.verticalCenter
                                  leftMargin: BarConfig.sp(10); rightMargin: BarConfig.sp(14); verticalCenterOffset: -BarConfig.sp(2) }
                        spacing: BarConfig.sp(3)
                        Text { width: parent.width; text: toastDelegate.app;     color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsSm; font.weight: Font.Medium; elide: Text.ElideRight }
                        Text { width: parent.width; text: toastDelegate.summary; color: Colors.colOnSurface;        font.pixelSize: BarConfig.fsMd; font.weight: Font.Bold;   elide: Text.ElideRight }
                        Text { width: parent.width; text: toastDelegate.body;    color: Colors.colOnSurfaceVariant; font.pixelSize: BarConfig.fsMd; elide: Text.ElideRight; visible: toastDelegate.body !== "" }
                    }

                    // Progress bar drains right→left inside the flat bottom area (no clipping needed)
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.left: parent.left
                        anchors.bottomMargin: toastWin._r - toastWin._ph
                        anchors.leftMargin: toastWin._r
                        height: toastWin._ph
                        radius: toastWin._ph / 2
                        color: Colors.primary
                        NumberAnimation on width {
                            from: toastWin._tw - toastWin._r * 2; to: 0
                            duration: 4000; easing.type: Easing.Linear
                            running: true
                        }
                    }
                }
            }
        }
    }
}