/* &desc: "WindowPlacement implementation -- window.open/destroy/workspace.removed/window.moveToWorkspace listeners on the stable EventBus." */
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

namespace {
void onWindowOpen(PHLWINDOW pWindow) {
    if (!pWindow || !pWindow->m_workspace)
        return;

    auto& state = RenderHook::stateFor(pWindow->m_workspace->m_id);
    if (!state.active())
        return; // not a canvas workspace right now -- open normally, untouched

    const auto monitor = pWindow->m_workspace->m_monitor.lock();
    if (!monitor)
        return;

    // getMouseCoordsInternal() returns *global* desktop coordinates
    // (matching `hyprctl cursorpos`, spanning every monitor's own layout
    // offset) -- but this workspace's whole canvas coordinate space is
    // monitor-relative, matching how the render hook computes its transform
    // relative to each monitor's own {0,0} origin. Convert global ->
    // monitor-relative before screenToCanvas.
    //
    // Nothing here touches the window's *real* Hyprland position at all --
    // unlike this plugin's first working approach (see RenderHook.cpp for
    // the full story of why that broke), canvas position is tracked
    // entirely independently, so there's no race to win against Hyprland's
    // own initial floating-window placement (centering) and no deferred
    // timer needed to beat it: whatever real position Hyprland ends up
    // giving this window is irrelevant to where it visually appears.
    const auto       cursorGlobal = g_pInputManager->getMouseCoordsInternal();
    const CanvasVec2 cursorLocal{cursorGlobal.x - monitor->m_position.x, cursorGlobal.y - monitor->m_position.y};
    const auto       canvasPos = Transform::screenToCanvas(state, cursorLocal);

    // Config::Actions functions are the same internal calls both the legacy
    // string-dispatcher table and the Lua hl.dsp.* bindings ultimately call
    // into -- calling them directly skips both layers (this system's Lua
    // config wraps hyprctl's "dispatch" command itself, breaking
    // invokeHyprctlCommand's string-based route entirely).
    Config::Actions::floatWindow(Config::Actions::TOGGLE_ACTION_ENABLE, pWindow);
    // Neither border/shadow decoration nor blur respect the canvas's
    // render-time transform (see Dispatchers.cpp's
    // setCanvasVisualsOnCurrentWorkspace comment for the full why on both)
    // -- a window opened *while* canvas mode is already on needs this
    // applied here too, since it never went through toggleImpl's sweep over
    // pre-existing windows.
    Config::Actions::setProp("decorate", "0", pWindow);
    Config::Actions::setProp("no_blur", "1", pWindow);
    RenderHook::setCanvasPos(pWindow, canvasPos);
}

void onWindowDestroy(PHLWINDOW pWindow) {
    RenderHook::forgetWindow(pWindow);
}

void onWorkspaceRemoved(PHLWORKSPACEREF wsRef) {
    if (const auto ws = wsRef.lock())
        RenderHook::forgetWorkspace(ws->m_id);
}

// A window carries its "decorate=0"/"no_blur=1" overrides (set by toggle-on
// or onWindowOpen above) with it if moved to a *different* workspace via a
// normal move-to-workspace action -- neither of those two call sites' sweep
// logic re-runs for a window that has already left the workspace they were
// scoped to, so without this it stays borderless/unblurred forever,
// anywhere, once a canvas workspace has ever touched it. Keeps both
// overrides in sync with wherever the window actually ends up: on if the
// destination is itself a canvas workspace, off (well, "unset" -- see
// setCanvasVisualsOnCurrentWorkspace) otherwise. Also drops the window's
// stored canvas position -- it was meaningful relative to the *old*
// workspace's camera, and would place the window somewhere arbitrary under
// the new one; the render hook re-derives a fresh one (from wherever the
// window's real position naturally is) the next time it renders.
void onWindowMovedToWorkspace(PHLWINDOW pWindow, PHLWORKSPACE pNewWorkspace) {
    if (!pWindow || !pNewWorkspace)
        return;

    RenderHook::forgetWindow(pWindow);

    const bool canvas = RenderHook::stateFor(pNewWorkspace->m_id).active();
    Config::Actions::setProp("decorate", canvas ? "0" : "unset", pWindow);
    Config::Actions::setProp("no_blur", canvas ? "1" : "unset", pWindow);
}
}

void WindowPlacement::registerListeners(HANDLE) {
    static auto P_OPEN     = Event::bus()->m_events.window.open.listen(onWindowOpen);
    static auto P_DESTROY  = Event::bus()->m_events.window.destroy.listen(onWindowDestroy);
    static auto P_REMOVED  = Event::bus()->m_events.workspace.removed.listen(onWorkspaceRemoved);
    static auto P_MOVED_WS = Event::bus()->m_events.window.moveToWorkspace.listen(onWindowMovedToWorkspace);
}
