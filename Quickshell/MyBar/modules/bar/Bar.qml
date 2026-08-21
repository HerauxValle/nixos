pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../config"
import "../../services"

Scope {
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() {
            const name = Hyprland.focusedMonitor?.name ?? ""
            if (name) BarConfig.primaryScreen = name
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property ShellScreen modelData
            screen: modelData

            color: "transparent"
            WlrLayershell.namespace: "quickshell:mybar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: barWindow.myPopupActive && (BarConfig.currentPopup === "barsettings" || BarConfig.capturingKey !== "")
                                         ? WlrKeyboardFocus.OnDemand
                                         : WlrKeyboardFocus.None

            // ── Anchors: all 4 positions ──────────────────────────────────
            anchors {
                top:    BarConfig.barPosition !== "bottom"
                bottom: BarConfig.barPosition === "bottom" || BarConfig.isVertical
                left:   BarConfig.barPosition !== "right"
                right:  BarConfig.barPosition !== "left"
            }

            // This screen's name — used to filter which bar shows its popup.
            readonly property string screenName: barWindow.screen.name

            readonly property bool myPopupActive: BarConfig.currentPopup !== "" && BarConfig.currentPopupScreen === barWindow.screenName

            // Inhibit compositor shortcuts during key capture so intercepted keys reach Qt
            ShortcutInhibitor {
                window: barWindow
                enabled: barWindow.myPopupActive && BarConfig.capturingKey !== ""
            }

            // Push screen height into BarConfig so sp() works everywhere
            Component.onCompleted: {
                BarConfig.screenH = barWindow.screen.height
                if (!BarConfig.primaryScreen) BarConfig.primaryScreen = barWindow.screenName
            }
            Connections {
                target: barWindow.screen
                function onHeightChanged() { BarConfig.screenH = barWindow.screen.height }
            }

            // Popup dimensions — relative to screen so they look right on all resolutions.
            readonly property int popupW: Math.round(barWindow.screen.width * 0.198)
            readonly property int popupH: {
                const maxH = Math.round(barWindow.screen.height * 0.60)
                switch(BarConfig.currentPopup) {
                    case "controlcenter": return Math.min(BarConfig.sp(365), maxH)
                    case "barsettings":   return Math.min(BarConfig.sp(420), maxH)
                    case "wifi":          return Math.min(BarConfig.sp(480), maxH)
                    case "bluetooth":     return Math.min(BarConfig.sp(420), maxH)
                    case "power":         return Math.min(BarConfig.sp(400), maxH)
                    case "workspacemenu":     return Math.min(BarConfig.sp(180), maxH)
                    case "airplanesettings": return Math.min(BarConfig.sp(360), maxH)
                    default: return 0
                }
            }

            // ── Auto-hide state ───────────────────────────────────────────
            property bool barPeeked: false  // true when mouse is near edge or hovering pill

            // ── Window size ───────────────────────────────────────────────
            // For vertical bars: implicitWidth drives the side strip width; implicitHeight
            // is ignored because both top+bottom anchors are set.
            // For horizontal bars: implicitHeight drives the window height (popup area);
            // implicitWidth is ignored because both left+right anchors are set.
            implicitWidth: BarConfig.isVertical
                           ? BarConfig.barHeight + barWindow.popupW
                           : 0   // ignored — left+right anchors fill screen width
            // Track last real popup height so close animation has space
            property int _lastPopupH: 340
            onPopupHChanged: if (popupH > 0) _lastPopupH = popupH

            // Constant height = pill + max popup. No resize animation → no flicker or white flash.
            // xray 1 in launch.sh makes the transparent area truly see-through (no 3-lines artifact).
            implicitHeight: BarConfig.isVertical ? 0
                            : BarConfig.barMargin + BarConfig.barHeight + BarConfig.sp(520)

            // ── Exclusive zone ────────────────────────────────────────────
            exclusiveZone: {
                const zone = BarConfig.isVertical
                             ? BarConfig.barHeight
                             : BarConfig.barMargin + BarConfig.barHeight
                return (!BarConfig.autoHide || barWindow.barPeeked || barWindow.myPopupActive)
                       ? zone : 0
            }

            // ── Computed pill geometry (avoids forward references in delegates) ─
            readonly property real pillW: {
                if (BarConfig.isVertical) return BarConfig.barHeight
                // hanging and pill: both use pillWidthPct; full mode deprecated
                return (barWindow.width - 16) * BarConfig.pillWidthPct
            }
            readonly property real pillH: BarConfig.isVertical ? barWindow.height : BarConfig.barHeight

            // ── Pill target Y (auto-hide slide for horizontal bars) ───────
            readonly property real pillTargetY: {
                if (BarConfig.isVertical) return 0
                if (!BarConfig.autoHide || barWindow.myPopupActive || barWindow.barPeeked) {
                    return BarConfig.barPosition === "bottom"
                        ? barWindow.height - BarConfig.barHeight - BarConfig.barMargin
                        : BarConfig.barMargin
                }
                return BarConfig.barPosition === "bottom"
                    ? barWindow.height + 4
                    : -(BarConfig.barHeight + BarConfig.barMargin + 4)
            }

            // ── Pill target X ─────────────────────────────────────────────
            readonly property real pillTargetX: {
                if (BarConfig.isVertical) {
                    if (!BarConfig.autoHide || barWindow.myPopupActive || barWindow.barPeeked) {
                        return BarConfig.barPosition === "right"
                            ? barWindow.width - BarConfig.barHeight
                            : 0
                    }
                    return BarConfig.barPosition === "right"
                        ? barWindow.width + 4
                        : -(BarConfig.barHeight + 4)
                }
                if (BarConfig.fillMode === "hanging") return 8
                const w = barWindow.pillW
                if (BarConfig.pillAlign === "left")  return 12
                if (BarConfig.pillAlign === "right")  return barWindow.width - w - 12
                return (barWindow.width - w) / 2
            }

            // ── Interactive mask: pill + open popup area ──────────────────
            mask: Region { item: maskItem }
            Item {
                id: maskItem
                readonly property int activeH: BarConfig.barMargin + BarConfig.barHeight +
                    (barWindow.myPopupActive || popupHost.keepMounted ? barWindow.popupH + 10 : 0)
                x: 0
                // Bottom bar: mask covers from pill downward; top bar: from 0
                y: (!BarConfig.isVertical && BarConfig.barPosition === "bottom")
                   ? barWindow.height - activeH : 0
                width:  barWindow.width
                height: BarConfig.isVertical ? barWindow.height : activeH
            }

            // ── Pill ──────────────────────────────────────────────────────
            BarContent {
                id: pill
                barScreenName: barWindow.screenName
                z: 6  // above backdrop (z:5) so pill clicks aren't eaten when popup is open

                width:  barWindow.pillW
                height: barWindow.pillH
                x:      barWindow.pillTargetX
                y:      barWindow.pillTargetY

                Behavior on x     { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
                Behavior on y     { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
                Behavior on width { NumberAnimation { duration: 180; easing.bezierCurve: Colors.spring } }
            }

            // ── Auto-hide: HoverHandler doesn't intercept clicks (MouseArea does!) ─
            // HoverHandler is separate from the pointer event chain — safe to use here.
            HoverHandler {
                id: pillHover
                // parent is pill via assignment below — but HoverHandler needs a parent Item
                // We attach it to the pill's bounding area via an invisible Item sibling
                parent: pill
                onHoveredChanged: {
                    if (hovered) barWindow.barPeeked = true
                    else hideTimer.restart()
                }
            }

            // Peek trigger: bare Item at screen edge (no MouseArea = no event interception)
            Item {
                id: peekTriggerArea
                x: BarConfig.isVertical ? (BarConfig.barPosition === "right" ? barWindow.width - 2 : 0) : 0
                y: (!BarConfig.isVertical && BarConfig.barPosition === "bottom") ? barWindow.height - 2 : 0
                width:  BarConfig.isVertical ? 2 : barWindow.width
                height: BarConfig.isVertical ? barWindow.height : 2

                HoverHandler {
                    id: peekTrigger
                    onHoveredChanged: if (hovered) barWindow.barPeeked = true
                }
            }

            // ── Hide timer ────────────────────────────────────────────────
            Timer {
                id: hideTimer
                interval: BarConfig.autoHideDelay
                onTriggered: {
                    if (!pillHover.hovered && !peekTrigger.hovered)
                        barWindow.barPeeked = false
                }
            }

            // ── Backdrop: closes popup when clicking outside ──────────────
            MouseArea {
                anchors.fill: parent
                visible: barWindow.myPopupActive
                z: 5
                onClicked: BarConfig.closePopup()
            }

            // ── Popup host ────────────────────────────────────────────────
            Item {
                id: popupHost
                visible: barWindow.myPopupActive || popupHost.keepMounted
                z: 10

                x: BarConfig.isVertical
                   ? (BarConfig.barPosition === "right"
                      ? barWindow.width - BarConfig.barHeight - barWindow.popupW - 6
                      : BarConfig.barHeight + 6)
                   : Math.max(4, pill.x + pill.width - barWindow.popupW - 12)
                // Always use _lastPopupH so y stays stable during open/close animation
                readonly property real _yOpen:   BarConfig.barPosition === "bottom" ? pill.y - barWindow._lastPopupH - 8  : pill.y + BarConfig.barHeight + 6
                readonly property real _yClosed: BarConfig.barPosition === "bottom" ? _yOpen + 14                          : _yOpen - 14
                y: BarConfig.isVertical ? 8 : (barWindow.myPopupActive ? _yOpen : _yClosed)

                width:  barWindow.popupW
                // During keepMounted, preserve last height so animation has space to play
                height: barWindow.myPopupActive ? barWindow.popupH
                        : (keepMounted ? barWindow._lastPopupH : 0)

                opacity: barWindow.myPopupActive ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on y       { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // Keep alive 350ms so exit animation completes before unmount
                property bool keepMounted: false
                property Timer unmountTimer: Timer {
                    interval: 350
                    onTriggered: popupHost.keepMounted = false
                }

                property string _prevPopup: ""

                Connections {
                    target: BarConfig
                    function onCurrentPopupChanged() {
                        if (BarConfig.currentPopup === "") {
                            popupHost.keepMounted = true
                            popupHost.unmountTimer.restart()
                            return
                        }
                        const prev = popupHost._prevPopup
                        const next = BarConfig.currentPopup
                        popupHost._prevPopup = next
                        ShellState.drawerOpen = false

                        const isCcBs = next === "controlcenter" || next === "barsettings"
                        const wasСcBs = prev === "controlcenter" || prev === "barsettings"

                        if (isCcBs && wasСcBs) {
                            const goingDeeper = (next === "barsettings")
                            // Outgoing: fade + scale down toward the leaving direction
                            // Incoming: start offset + scaled down, animate to center + full scale
                            if (goingDeeper) {
                                ccLoader.opacity = 1; ccLoader.scale = 1
                                bsLoader.opacity = 0; bsLoader.scale = 0.97
                            } else {
                                bsLoader.opacity = 1; bsLoader.scale = 1
                                ccLoader.opacity = 0; ccLoader.scale = 0.97
                            }
                            ccFadeAnim.to = (next === "controlcenter") ? 1 : 0; ccFadeAnim.restart()
                            bsFadeAnim.to = (next === "barsettings")   ? 1 : 0; bsFadeAnim.restart()
                            ccScaleAnim.to = (next === "controlcenter") ? 1 : 0.97; ccScaleAnim.restart()
                            bsScaleAnim.to = (next === "barsettings")   ? 1 : 0.97; bsScaleAnim.restart()
                            if (next === "barsettings" && bsLoader.item)
                                Qt.callLater(() => { if (bsLoader.item) bsLoader.item.forceActiveFocus() })
                            else if (next === "controlcenter" && ccLoader.item)
                                Qt.callLater(() => { if (ccLoader.item) ccLoader.item.forceActiveFocus() })
                        } else {
                            // Snap to correct state for first open
                            ccLoader.opacity = (next === "controlcenter") ? 1 : 0; ccLoader.scale = 1
                            bsLoader.opacity = (next === "barsettings")   ? 1 : 0; bsLoader.scale = 1
                            const src = (function() { switch(next) {
                                case "wifi":             return "../popups/WiFiSettings.qml"
                                case "bluetooth":        return "../popups/BluetoothSettings.qml"
                                case "power":            return "../popups/PowerMenu.qml"
                                case "workspacemenu":    return "../popups/WorkspaceMenu.qml"
                                case "airplanesettings": return "../popups/AirplaneSettings.qml"
                                default: return ""
                            }})()
                            if (src !== "") otherLoader._lastSource = src
                        }
                    }
                }

                Connections {
                    target: ShellState
                    function onDrawerOpenChanged() {
                        if (ShellState.drawerOpen) BarConfig.closePopup()
                    }
                }

                // Generic loader for wifi/bt/power/etc
                Loader {
                    id: otherLoader
                    anchors.fill: parent
                    property string _lastSource: ""
                    source: _lastSource
                    active: barWindow.myPopupActive || popupHost.keepMounted
                    visible: BarConfig.currentPopup !== "controlcenter" && BarConfig.currentPopup !== "barsettings"
                    onLoaded: {
                        if (item && "barScreenName" in item) item.barScreenName = barWindow.screenName
                        if (item) item.forceActiveFocus()
                    }
                }

                // CC and BarSettings stacked, scale+fade between them
                Loader {
                    id: ccLoader
                    anchors.fill: parent
                    source: "../popups/ControlCenter.qml"
                    active: barWindow.myPopupActive || popupHost.keepMounted
                    visible: opacity > 0
                    transformOrigin: Item.Center
                    NumberAnimation { id: ccFadeAnim;  target: ccLoader; property: "opacity"; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { id: ccScaleAnim; target: ccLoader; property: "scale";   duration: 260; easing.type: Easing.OutCubic }
                    onLoaded: {
                        if (item && "barScreenName" in item) item.barScreenName = barWindow.screenName
                        if (item && BarConfig.currentPopup === "controlcenter") item.forceActiveFocus()
                    }
                }

                Loader {
                    id: bsLoader
                    anchors.fill: parent
                    source: "../popups/BarSettings.qml"
                    active: barWindow.myPopupActive || popupHost.keepMounted
                    opacity: 0
                    scale: 0.97
                    visible: opacity > 0
                    transformOrigin: Item.Center
                    NumberAnimation { id: bsFadeAnim;  target: bsLoader; property: "opacity"; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { id: bsScaleAnim; target: bsLoader; property: "scale";   duration: 260; easing.type: Easing.OutCubic }
                    onLoaded: {
                        if (item && "barScreenName" in item) item.barScreenName = barWindow.screenName
                        if (item && BarConfig.currentPopup === "barsettings") item.forceActiveFocus()
                    }
                }
            }
        }
    }
}
