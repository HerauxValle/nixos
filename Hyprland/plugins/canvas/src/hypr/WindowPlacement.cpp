/* &desc: "WindowPlacement implementation -- window.open/workspace.removed listeners on the stable EventBus." */
#include "WindowPlacement.hpp"
#include "RenderHook.hpp"

#include "../canvas/Transform.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>

namespace {
void onWindowOpen(PHLWINDOW pWindow) {
    if (!pWindow || !pWindow->m_workspace)
        return;

    auto& state = RenderHook::stateFor(pWindow->m_workspace->m_id);
    if (!state.active())
        return; // not a canvas workspace right now -- open normally, untouched

    const auto cursor    = g_pInputManager->getMouseCoordsInternal();
    const auto canvasPos = Transform::screenToCanvas(state, {cursor.x, cursor.y});

    // Config::Actions functions are the same internal calls both the legacy
    // string-dispatcher table and the Lua hl.dsp.* bindings ultimately call
    // into -- calling them directly skips both layers (this system's Lua
    // config wraps hyprctl's "dispatch" command itself, breaking
    // invokeHyprctlCommand's string-based route entirely).
    Config::Actions::floatWindow(Config::Actions::TOGGLE_ACTION_ENABLE, pWindow);
    Config::Actions::move(Vector2D{canvasPos.x, canvasPos.y}, false, pWindow);
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
