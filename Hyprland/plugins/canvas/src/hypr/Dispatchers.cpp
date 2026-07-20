/* &desc: "Dispatcher callbacks -- the only translation point between bind-triggered strings/Lua calls and per-workspace CCanvasState." */
#include "Dispatchers.hpp"
#include "RenderHook.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/helpers/Monitor.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <format>

namespace {
HANDLE g_handle = nullptr; // TEMPORARY, for diagnostic notifications only

constexpr double ZOOM_STEP_IN  = 1.25;
constexpr double ZOOM_STEP_OUT = 0.8;
constexpr double PAN_STEP      = 80.0; // canvas units per discrete keyboard step

// "The workspace this action applies to" -- the active workspace of
// whichever monitor the cursor is over. Every dispatcher here is either
// keyboard-triggered (acts on wherever you're looking) or mouse-triggered
// (scroll/drag, inherently cursor-based already), so the cursor's monitor
// is the right notion of "current" for both.
WORKSPACEID currentWorkspaceID() {
    const auto mon = g_pCompositor->getMonitorFromCursor();
    if (!mon || !mon->m_activeWorkspace)
        return WORKSPACE_INVALID;
    return mon->m_activeWorkspace->m_id;
}

CCanvasState& currentState() {
    return RenderHook::stateFor(currentWorkspaceID());
}

// Canvas mode is floating-only (windows placed freely, like ComfyUI nodes,
// rather than auto-arranged). Existing windows on a workspace need floating
// the moment it enters canvas mode; new ones are handled separately by
// WindowPlacement.cpp's window.open listener.
void floatAllWindowsOnCurrentWorkspace() {
    const auto id = currentWorkspaceID();
    for (auto& w : g_pCompositor->m_windows) {
        if (!w || !w->m_workspace || w->m_workspace->m_id != id || w->m_isFloating)
            continue;
        // Config::Actions functions are the same internal calls both the
        // legacy string-dispatcher table and the Lua hl.dsp.* bindings
        // ultimately call into -- calling them directly here skips both of
        // those layers entirely (this system's Lua config wraps hyprctl's
        // "dispatch" command itself, which broke invokeHyprctlCommand too).
        const auto result = Config::Actions::floatWindow(Config::Actions::TOGGLE_ACTION_ENABLE, w);
        if (!result)
            HyprlandAPI::addNotification(g_handle, "[canvas diag] floatWindow failed for " + w->m_title + ": " + result.error().message, CHyprColor{1.0, 1.0, 0.2, 1.0}, 8000);
    }
}

// Actual behavior lives here, called from both addDispatcherV2 callbacks
// (legacy bind = ... syntax, string-based) and addLuaFunction callbacks
// (this system's Lua config calls hl.plugin.canvas.<name>(...) directly --
// confirmed the working convention empirically against the already-loaded
// scrolloverview plugin, since addDispatcherV2 alone isn't reachable from
// Lua-authored binds here).
void toggleImpl() {
    auto& state = currentState();
    state.toggle();
    if (state.active())
        floatAllWindowsOnCurrentWorkspace();
}

void zoomImpl(const std::string& arg) {
    auto& state = currentState();
    if (arg == "in")
        state.zoomBy(ZOOM_STEP_IN);
    else if (arg == "out")
        state.zoomBy(ZOOM_STEP_OUT);
    else if (!arg.empty()) {
        char*        end = nullptr;
        const double v   = std::strtod(arg.c_str(), &end);
        if (end != arg.c_str())
            state.zoomTo(v);
    }
}

void panImpl(const std::string& arg) {
    auto& state = currentState();
    if (arg == "up")
        state.panBy({.x = 0, .y = -PAN_STEP});
    else if (arg == "down")
        state.panBy({.x = 0, .y = PAN_STEP});
    else if (arg == "left")
        state.panBy({.x = -PAN_STEP, .y = 0});
    else if (arg == "right")
        state.panBy({.x = PAN_STEP, .y = 0});
}

// Fires repeatedly while a drag button is held and the mouse moves, with no
// press/release signal available to the callback itself -- so "is this the
// first call of a new drag" is inferred from a time gap since the last call
// rather than a real begin/end hook. Simple, tunable heuristic; revisit if
// it ever feels laggy or jumpy in practice (see DESIGN.md open risks).
Vector2D                              g_lastDragPos{};
std::chrono::steady_clock::time_point g_lastDragCall{};
constexpr std::chrono::milliseconds   DRAG_GAP_RESET{150};

void panDragImpl() {
    auto&      state = currentState();
    const auto now   = std::chrono::steady_clock::now();
    const auto pos   = g_pInputManager->getMouseCoordsInternal();

    const bool freshDrag = (now - g_lastDragCall) > DRAG_GAP_RESET;

    if (!freshDrag) {
        const double scale = std::max(0.0001, state.currentScale());
        state.panBy({
            .x = (g_lastDragPos.x - pos.x) / scale,
            .y = (g_lastDragPos.y - pos.y) / scale,
        });
    }

    g_lastDragPos  = pos;
    g_lastDragCall = now;
}

void resetImpl() {
    currentState().reset();
}

// -- addDispatcherV2 callbacks (legacy `bind = MOD, KEY, name, arg` config) --

SDispatchResult dispatchToggle(std::string) {
    toggleImpl();
    return {};
}
SDispatchResult dispatchZoom(std::string arg) {
    zoomImpl(arg);
    return {};
}
SDispatchResult dispatchPan(std::string arg) {
    panImpl(arg);
    return {};
}
SDispatchResult dispatchPanDrag(std::string) {
    panDragImpl();
    return {};
}
SDispatchResult dispatchReset(std::string) {
    resetImpl();
    return {};
}

// -- addLuaFunction callbacks (hl.plugin.canvas.<name>(...) from Lua config) --

std::string argStringOr(lua_State* L, int idx, const std::string& fallback) {
    if (lua_gettop(L) >= idx && lua_isstring(L, idx))
        return lua_tostring(L, idx);
    return fallback;
}

int luaToggle(lua_State*) {
    toggleImpl();
    return 0;
}
int luaZoom(lua_State* L) {
    zoomImpl(argStringOr(L, 1, ""));
    return 0;
}
int luaPan(lua_State* L) {
    panImpl(argStringOr(L, 1, ""));
    return 0;
}
int luaPanDrag(lua_State*) {
    panDragImpl();
    return 0;
}
int luaReset(lua_State*) {
    resetImpl();
    return 0;
}
}

void Dispatchers::registerAll(HANDLE handle) {
    g_handle = handle;

    HyprlandAPI::addDispatcherV2(handle, "toggle", dispatchToggle);
    HyprlandAPI::addDispatcherV2(handle, "zoom", dispatchZoom);
    HyprlandAPI::addDispatcherV2(handle, "pan", dispatchPan);
    HyprlandAPI::addDispatcherV2(handle, "panDrag", dispatchPanDrag);
    HyprlandAPI::addDispatcherV2(handle, "reset", dispatchReset);

    HyprlandAPI::addLuaFunction(handle, "canvas", "toggle", luaToggle);
    HyprlandAPI::addLuaFunction(handle, "canvas", "zoom", luaZoom);
    HyprlandAPI::addLuaFunction(handle, "canvas", "pan", luaPan);
    HyprlandAPI::addLuaFunction(handle, "canvas", "panDrag", luaPanDrag);
    HyprlandAPI::addLuaFunction(handle, "canvas", "reset", luaReset);
}
