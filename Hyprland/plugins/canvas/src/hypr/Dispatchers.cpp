/* &desc: "Dispatcher callbacks -- the only translation point between bind-triggered strings/Lua calls and per-workspace CCanvasState." */
#include "Dispatchers.hpp"
#include "RenderHook.hpp"

#include "../canvas/Transform.hpp"

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
HANDLE g_handle = nullptr; // for the occasional user-facing warning notification

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

// Cursor position in monitor-relative coordinates -- getMouseCoordsInternal()
// returns *global* desktop coordinates (matching `hyprctl cursorpos`), but
// the render hook's translate/scale (and so canvas space) are monitor-
// relative, matching how renderAllClientsForWorkspace itself operates on a
// {0,0}-origin box for its own monitor. Returns {0,0} if no monitor is under
// the cursor (shouldn't normally happen).
CanvasVec2 cursorLocal() {
    const auto mon    = g_pCompositor->getMonitorFromCursor();
    const auto cursor = g_pInputManager->getMouseCoordsInternal();
    if (!mon)
        return {.x = cursor.x, .y = cursor.y};
    return {.x = cursor.x - mon->m_position.x, .y = cursor.y - mon->m_position.y};
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
            HyprlandAPI::addNotification(g_handle, "[canvas] Couldn't float \"" + w->m_title + "\": " + result.error().message, CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);
    }
}

// Window border/shadow decorations are drawn from a window's *real* geometry
// and never consult Hyprland's render-modifier (SRenderModifData) pipeline
// at all -- confirmed against the real source (CHyprBorderDecoration::draw,
// CHyprDropShadowDecoration::getRenderData): only surface content
// (CSurfacePassElement) respects it. So while a workspace is panned/zoomed,
// a window's border/shadow render at full real size in the real (unscaled)
// position while its content correctly shrinks and moves inside that outline
// -- confirmed live via screenshot, looked exactly like a stray glass pane
// with a small scaled screenshot floating inside it. Faking scale onto
// decorations would need hooking multiple additional, deeper, more fragile
// render internals (border boxes are baked eagerly at queue time; shadow and
// inner-glow are computed lazily from a separate code path). Turning
// decoration off entirely for the duration of canvas mode sidesteps that
// whole class of desync -- and fits the ComfyUI-node aesthetic this plugin
// is going for anyway (bare content, no native window chrome). Uses the same
// direct Config::Actions::setProp call hyprctl's own "setprop" dispatcher
// resolves to (see Config::Actions::floatWindow's comment above for why
// direct calls, not invokeHyprctlCommand, are this plugin's mechanism).
// "unset" restores whatever decorate value config/window rules had before --
// not hardcoding it back to enabled, in case a rule already disabled it.
void setDecorateOnCurrentWorkspace(bool decorate) {
    const auto id = currentWorkspaceID();
    for (auto& w : g_pCompositor->m_windows) {
        if (!w || !w->m_workspace || w->m_workspace->m_id != id)
            continue;
        Config::Actions::setProp("decorate", decorate ? "unset" : "0", w);
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
    setDecorateOnCurrentWorkspace(!state.active());

    // toggle() alone never touches zoom/pan, so at 1:1/no-pan it's a
    // no-visible-change identity transform -- easy to mistake for "the bind
    // isn't working" when it's actually just waiting for you to zoom/pan.
    // A brief confirmation makes that state visible either way.
    HyprlandAPI::addNotification(g_handle, std::string("[canvas] ") + (state.active() ? "ON -- scroll or drag to zoom/pan" : "OFF"),
                                  state.active() ? CHyprColor{0.2, 1.0, 0.4, 1.0} : CHyprColor{0.6, 0.6, 0.6, 1.0}, 2500);
}

void zoomImpl(const std::string& arg) {
    auto&      state  = currentState();
    const auto cursor = cursorLocal();

    // Anchor the zoom on whatever canvas point is currently under the
    // cursor (matching scroll-to-zoom in ComfyUI/most editors) -- without
    // this, zoom always keeps canvas-origin fixed on screen, so zooming out
    // flings your content into the top-left corner and reveals mostly-empty
    // canvas space around it. Confirmed live: this was the actual cause
    // behind "zooming out looks broken/black", not a rendering bug.
    const auto anchorCanvas = Transform::screenToCanvas(state, cursor);

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

    // Re-derive pan so that same canvas point ends up back under the
    // cursor at the new target scale: screenPos = (canvasPos - pan) * scale
    // => pan = canvasPos - screenPos / scale.
    const double newScale = state.targetScale();
    state.panTo({
        .x = anchorCanvas.x - cursor.x / newScale,
        .y = anchorCanvas.y - cursor.y / newScale,
    });
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
