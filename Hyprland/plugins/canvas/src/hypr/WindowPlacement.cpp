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
#include <fstream>
#include <vector>

namespace {
HANDLE                            g_handle = nullptr; // TEMPORARY, for diagnostic notifications only
std::vector<SP<CEventLoopTimer>> g_pendingPlacementTimers;

// TEMPORARY diagnostic: file logging instead of on-screen notifications --
// notifications are too easy to miss with screenshot timing; this is a
// plain, always-readable trace of what actually happened and when.
void dlog(const std::string& msg) {
    std::ofstream f("/tmp/canvas-debug.log", std::ios::app);
    f << msg << "\n";
}

void placeOnCanvas(PHLWINDOW pWindow) {
    dlog("placeOnCanvas: fired");
    if (!pWindow || !pWindow->m_isMapped || !pWindow->m_workspace) {
        dlog("placeOnCanvas: bailed (null/unmapped/no workspace)");
        return;
    }

    auto& state = RenderHook::stateFor(pWindow->m_workspace->m_id);
    if (!state.active()) {
        dlog("placeOnCanvas: bailed (workspace no longer active)");
        return; // canvas mode was turned off in the meantime -- leave it alone
    }

    const auto monitor = pWindow->m_workspace->m_monitor.lock();
    if (!monitor) {
        dlog("placeOnCanvas: bailed (no monitor)");
        return;
    }

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
    const Vector2D   target{canvasPos.x + monitor->m_position.x, canvasPos.y + monitor->m_position.y};

    dlog("placeOnCanvas: cursorGlobal=(" + std::to_string(cursorGlobal.x) + "," + std::to_string(cursorGlobal.y) + ") monitorPos=(" + std::to_string(monitor->m_position.x) + "," +
         std::to_string(monitor->m_position.y) + ") scale=" + std::to_string(state.currentScale()) + " target=(" + std::to_string(target.x) + "," + std::to_string(target.y) + ")");

    // Config::Actions functions are the same internal calls both the legacy
    // string-dispatcher table and the Lua hl.dsp.* bindings ultimately call
    // into -- calling them directly skips both layers (this system's Lua
    // config wraps hyprctl's "dispatch" command itself, breaking
    // invokeHyprctlCommand's string-based route entirely).
    const auto floatResult = Config::Actions::floatWindow(Config::Actions::TOGGLE_ACTION_ENABLE, pWindow);
    dlog(std::string("placeOnCanvas: floatWindow ") + (floatResult ? "ok" : ("FAILED: " + floatResult.error().message)));
    const auto moveResult = Config::Actions::move(target, false, pWindow);
    dlog(std::string("placeOnCanvas: move ") + (moveResult ? "ok" : ("FAILED: " + moveResult.error().message)));
    dlog("placeOnCanvas: immediately after -- isFloating=" + std::to_string(pWindow->m_isFloating) + " goal=(" + std::to_string(pWindow->m_realPosition->goal().x) + "," +
         std::to_string(pWindow->m_realPosition->goal().y) + ") value=(" + std::to_string(pWindow->m_realPosition->value().x) + "," +
         std::to_string(pWindow->m_realPosition->value().y) + ")");

    // TEMPORARY diagnostic: check again later to see if something else
    // (re-centering logic running after ours) overwrites the position.
    SP<CEventLoopTimer> verifyTimer = makeShared<CEventLoopTimer>(
        std::chrono::milliseconds(600),
        [pWindow](SP<CEventLoopTimer> self, void*) {
            if (pWindow)
                dlog("placeOnCanvas: 600ms later -- isFloating=" + std::to_string(pWindow->m_isFloating) + " goal=(" + std::to_string(pWindow->m_realPosition->goal().x) + "," +
                     std::to_string(pWindow->m_realPosition->goal().y) + ") value=(" + std::to_string(pWindow->m_realPosition->value().x) + "," +
                     std::to_string(pWindow->m_realPosition->value().y) + ")");
            std::erase(g_pendingPlacementTimers, self);
        },
        nullptr);
    g_pendingPlacementTimers.push_back(verifyTimer);
    g_pEventLoopManager->addTimer(verifyTimer);
}

void onWindowOpen(PHLWINDOW pWindow) {
    if (!pWindow || !pWindow->m_workspace) {
        dlog("onWindowOpen: bailed (null window/workspace)");
        return;
    }

    const bool active = RenderHook::stateFor(pWindow->m_workspace->m_id).active();
    dlog("onWindowOpen: ws=" + std::to_string(pWindow->m_workspace->m_id) + " active=" + (active ? "true" : "false"));
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
