/* &desc: "WindowPlacement implementation -- window.open/workspace.removed listeners on the stable EventBus." */
#include "WindowPlacement.hpp"
#include "RenderHook.hpp"

#include "../canvas/Transform.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/Workspace.hpp>

#include <format>

namespace {
void onWindowOpen(PHLWINDOW pWindow) {
    if (!pWindow || !pWindow->m_workspace)
        return;

    auto& state = RenderHook::stateFor(pWindow->m_workspace->m_id);
    if (!state.active())
        return; // not a canvas workspace right now -- open normally, untouched

    const auto cursor    = g_pInputManager->getMouseCoordsInternal();
    const auto canvasPos = Transform::screenToCanvas(state, {cursor.x, cursor.y});
    const auto addr      = std::format("0x{:x}", (uintptr_t)pWindow.get());

    // Reuses Hyprland's own setfloating/movewindowpixel dispatchers (via
    // hyprctl) rather than poking m_isFloating/position directly -- those
    // dispatchers already handle the layout-removal/geometry bookkeeping
    // that comes with floating a window, which isn't something to
    // reimplement here.
    HyprlandAPI::invokeHyprctlCommand("dispatch", "setfloating address:" + addr + " 1");
    HyprlandAPI::invokeHyprctlCommand("dispatch", "movewindowpixel exact " + std::to_string((int)canvasPos.x) + " " + std::to_string((int)canvasPos.y) + ",address:" + addr);
}

void onWorkspaceRemoved(PHLWORKSPACEREF wsRef) {
    if (const auto ws = wsRef.lock())
        RenderHook::forgetWorkspace(ws->m_id);
}
}

void WindowPlacement::registerListeners(HANDLE) {
    static auto P_OPEN    = Event::bus()->m_events.window.open.listen(onWindowOpen);
    static auto P_REMOVED = Event::bus()->m_events.workspace.removed.listen(onWorkspaceRemoved);
}
