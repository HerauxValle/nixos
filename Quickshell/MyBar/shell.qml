import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "modules/bar"
import "modules/osd"
import "modules/drawer"
import "modules/launcher"
import "modules/notifications"
import "config"
import "services"

ShellRoot {
    Bar {}
    OSD {}
    Drawer {}
    Launcher {}
    NotificationToast {}

    IpcHandler {
        target: "drawer"
        function onMessage(message: string) { ShellState.toggleDrawer() }
    }
    IpcHandler {
        target: "launcher"
        function onMessage(message: string) { ShellState.toggleLauncher() }
    }
    IpcHandler {
        target: "controlcenter"
        function onMessage(message: string) { BarConfig.togglePopup("controlcenter", Hyprland.focusedMonitor?.name ?? "") }
    }
    IpcHandler {
        target: "power"
        function onMessage(message: string) { BarConfig.togglePopup("power", Hyprland.focusedMonitor?.name ?? "") }
    }
    IpcHandler {
        target: "settings"
        function onMessage(message: string) { BarConfig.openBarSettings(Hyprland.focusedMonitor?.name ?? "") }
    }
    IpcHandler {
        target: "notifications"
        function onMessage(message: string) {
            if (ShellState.drawerOpen && ShellState.drawerTab === 2) ShellState.closeDrawer()
            else ShellState.openDrawerTab(2)
        }
    }
    IpcHandler {
        target: "wifi"
        function onMessage(message: string) { BarConfig.togglePopup("wifi", Hyprland.focusedMonitor?.name ?? "") }
    }
    IpcHandler {
        target: "bluetooth"
        function onMessage(message: string) { BarConfig.togglePopup("bluetooth", Hyprland.focusedMonitor?.name ?? "") }
    }
    IpcHandler {
        target: "workspacemenu"
        function onMessage(message: string) {
            BarConfig.ctxWorkspaceId = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1
            BarConfig.togglePopup("workspacemenu", Hyprland.focusedMonitor?.name ?? "")
        }
    }
    // Next/prev workspace switch and window-move, direction-aware of
    // BarConfig.invertWorkspaceIds -- Hyprland's workspaces slide animation
    // is fixed to raw-ID comparison with no config override (confirmed:
    // hyprwm/Hyprland discussion #3828), so flipping e+1/e-1 here is what
    // actually reverses it while Workspaces.qml keeps displayed numbers
    // unchanged. Bound from Config/Reactive/windowMode.lua via "qs ipc call".
    IpcHandler {
        target: "workspacefocusnext"
        function onMessage(message: string) { Hyprland.dispatch("workspace " + (BarConfig.invertWorkspaceIds ? "e-1" : "e+1")) }
    }
    IpcHandler {
        target: "workspacefocusprev"
        function onMessage(message: string) { Hyprland.dispatch("workspace " + (BarConfig.invertWorkspaceIds ? "e+1" : "e-1")) }
    }
    IpcHandler {
        target: "workspacemovenext"
        function onMessage(message: string) { Hyprland.dispatch("movetoworkspace " + (BarConfig.invertWorkspaceIds ? "e-1" : "e+1")) }
    }
    IpcHandler {
        target: "workspacemoveprev"
        function onMessage(message: string) { Hyprland.dispatch("movetoworkspace " + (BarConfig.invertWorkspaceIds ? "e+1" : "e-1")) }
    }

    Connections {
        target: BarConfig
        function onTintIndexChanged() {
            const palettes = [
                // 0: Aether Ridge (default)
                { primary:"#5C8FA5", surface:"#08141A", surfC:"#0D1E28", surfCH:'#487d96', popupBg:"#D6081220", popupBorder:"#28FFFFFF", text:"#EAF4F8", muted:"#9EB5BF", outline:"#1E3A4A", outlineV:"#122530", onPrimary:"#04141E" },
                // 1: Purple
                { primary:"#A78BFA", surface:"#0D0A1E", surfC:"#16112A", surfCH:"#201B35", popupBg:"#D60D0A16", popupBorder:"#40FFFFFF", text:"#EDE8FF", muted:"#C4B5FD", outline:"#3D2B6B", outlineV:"#261A45", onPrimary:"#0D0A20" },
                // 2: Green
                { primary:"#34D399", surface:"#081E0E", surfC:"#0B2914", surfCH:"#12381C", popupBg:"#D6060E08", popupBorder:"#40FFFFFF", text:"#E8FFF2", muted:"#6EE7B7", outline:"#0D4A2B", outlineV:"#082D1A", onPrimary:"#041A0A" },
                // 3: Amber
                { primary:"#F59E0B", surface:"#1E120A", surfC:"#29180D", surfCH:"#352015", popupBg:"#D6140D04", popupBorder:"#40FFFFFF", text:"#FFF8E8", muted:"#FCD34D", outline:"#6B3D06", outlineV:"#3D2204", onPrimary:"#1A0A00" },
                // 4: Pink
                { primary:"#F472B6", surface:"#1E0A12", surfC:"#2A0D1A", surfCH:"#381524", popupBg:"#D6160A0C", popupBorder:"#40FFFFFF", text:"#FFE8F5", muted:"#FBCFE8", outline:"#6B1A3D", outlineV:"#3D0D24", onPrimary:"#1A0408" },
                // 5: Blue
                { primary:"#60A5FA", surface:"#0A0F1E", surfC:"#0D1529", surfCH:"#152038", popupBg:"#D6080B16", popupBorder:"#40FFFFFF", text:"#E8F0FF", muted:"#93C5FD", outline:"#1A3A6B", outlineV:"#0D2040", onPrimary:"#030814" },
            ]
            const p = palettes[Math.min(BarConfig.tintIndex, palettes.length - 1)]
            Colors.primary              = Qt.color(p.primary)
            Colors.surface              = Qt.color(p.surface)
            Colors.surfaceContainer     = Qt.color(p.surfC)
            Colors.surfaceContainerHigh = Qt.color(p.surfCH)
            Colors.popupBg              = Qt.color(p.popupBg)
            Colors.popupBorder          = Qt.color(p.popupBorder)
            Colors.colOnSurface         = Qt.color(p.text)
            Colors.colOnSurfaceVariant  = Qt.color(p.muted)
            Colors.outline              = Qt.color(p.outline)
            Colors.outlineVariant       = Qt.color(p.outlineV)
            Colors.colOnPrimary         = Qt.color(p.onPrimary)
        }
    }
}
