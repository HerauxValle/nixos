/* &desc: "WindowPlacement implementation -- window.open/workspace.removed listeners on the stable EventBus." */
#include "WindowPlacement.hpp"
#include "RenderHook.hpp"

#include "../canvas/Transform.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/helpers/Monitor.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>

#include <algorithm>
#include <vector>

namespace {
HANDLE                            g_handle = nullptr; // TEMPORARY, for diagnostic notifications only
std::vector<SP<CEventLoopTimer>> g_pendingPlacementTimers;

void placeOnCanvas(PHLWINDOW pWindow) {
    if (!pWindow || !pWindow->m_isMapped || !pWindow->m_workspace)
        return;

    auto& state = RenderHook::stateFor(pWindow->m_workspace->m_id);
    if (!state.active())
        return; // canvas mode was turned off in the meantime -- leave it alone

    const auto monitor = pWindow->m_workspace->m_monitor.lock();
    if (!monitor)
        return;

    // getMouseCoordsInternal() returns *global* desktop coordinates
    // (matching `hyprctl cursorpos`, spanning every monitor's own layout
    // offset) -- but the render hook's translate/scale (and so our whole
    // canvas coordinate space) are monitor-relative, matching how
    // renderAllClientsForWorkspace itself operates on a {0,0}-origin box
    // for its own monitor. Convert global -> monitor-relative before
    // screenToCanvas, then back to global before Config::Actions::move
    // (which, like window positions in general, is global-coordinate).
    const auto       cursorGlobal = g_pInputManager->getMouseCoordsInternal();
    const CanvasVec2 cursorLocal{cursorGlobal.x - monitor->m_position.x, cursorGlobal.y - monitor->m_position.y};
    const auto       canvasPos = Transform::screenToCanvas(state, cursorLocal);

    // Config::Actions functions are the same internal calls both the legacy
    // string-dispatcher table and the Lua hl.dsp.* bindings ultimately call
    // into -- calling them directly skips both layers (this system's Lua
    // config wraps hyprctl's "dispatch" command itself, breaking
    // invokeHyprctlCommand's string-based route entirely).
    Config::Actions::floatWindow(Config::Actions::TOGGLE_ACTION_ENABLE, pWindow);
    Config::Actions::move(Vector2D{canvasPos.x + monitor->m_position.x, canvasPos.y + monitor->m_position.y}, false, pWindow);
}

void onWindowOpen(PHLWINDOW pWindow) {
    if (!pWindow || !pWindow->m_workspace)
        return;

    const bool active = RenderHook::stateFor(pWindow->m_workspace->m_id).active();
    // TEMPORARY diagnostic: see exactly what state onWindowOpen observes.
    HyprlandAPI::addNotification(g_handle, "[canvas diag] onWindowOpen ws=" + std::to_string(pWindow->m_workspace->m_id) + " active=" + (active ? "true" : "false"),
                                  CHyprColor{0.2, 0.6, 1.0, 1.0}, 8000);
    if (!active)
        return; // not a canvas workspace right now -- open normally, untouched

    // Hyprland's own initial floating-window placement (e.g. centering on
    // the monitor) runs some time after "open" fires and would otherwise
    // clobber our positioning if applied immediately -- confirmed live: an
    // immediate move() landed exactly at the monitor's centered-floating
    // default instead of the cursor position we asked for. A short deferred
    // timer lets that settle first, so ours is the last word.
    SP<CEventLoopTimer> timer = makeShared<CEventLoopTimer>(
        std::chrono::milliseconds(50),
        [pWindow](SP<CEventLoopTimer> self, void*) {
            placeOnCanvas(pWindow);
            std::erase(g_pendingPlacementTimers, self);
        },
        nullptr);
    g_pendingPlacementTimers.push_back(timer);
    g_pEventLoopManager->addTimer(timer);
}

void onWorkspaceRemoved(PHLWORKSPACEREF wsRef) {
    if (const auto ws = wsRef.lock())
        RenderHook::forgetWorkspace(ws->m_id);
}
}

void WindowPlacement::registerListeners(HANDLE handle) {
    g_handle = handle;

    static auto P_OPEN    = Event::bus()->m_events.window.open.listen(onWindowOpen);
    static auto P_REMOVED = Event::bus()->m_events.workspace.removed.listen(onWorkspaceRemoved);
}
