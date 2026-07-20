/* &desc: "Dispatcher callbacks -- the only translation point between bind-triggered strings and CCanvasState." */
#include "Dispatchers.hpp"
#include "RenderHook.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>

#include <algorithm>
#include <chrono>
#include <cstdlib>

namespace {
constexpr double ZOOM_STEP_IN  = 1.25;
constexpr double ZOOM_STEP_OUT = 0.8;
constexpr double PAN_STEP      = 80.0; // canvas units per discrete keyboard step

SDispatchResult dispatchToggle(std::string) {
    RenderHook::state().toggle();
    return {};
}

SDispatchResult dispatchZoom(std::string arg) {
    if (arg == "in")
        RenderHook::state().zoomBy(ZOOM_STEP_IN);
    else if (arg == "out")
        RenderHook::state().zoomBy(ZOOM_STEP_OUT);
    else if (!arg.empty()) {
        char* end     = nullptr;
        const double v = std::strtod(arg.c_str(), &end);
        if (end != arg.c_str())
            RenderHook::state().zoomTo(v);
    }
    return {};
}

SDispatchResult dispatchPan(std::string arg) {
    if (arg == "up")
        RenderHook::state().panBy({.x = 0, .y = -PAN_STEP});
    else if (arg == "down")
        RenderHook::state().panBy({.x = 0, .y = PAN_STEP});
    else if (arg == "left")
        RenderHook::state().panBy({.x = -PAN_STEP, .y = 0});
    else if (arg == "right")
        RenderHook::state().panBy({.x = PAN_STEP, .y = 0});
    return {};
}

// bindm fires this repeatedly while the button is held and the mouse moves,
// with no press/release signal available to the dispatcher itself (its
// string arg is static config text, not a live event) -- so "is this the
// first call of a new drag" is inferred from a time gap since the last call
// rather than a real begin/end hook. Simple, tunable heuristic; revisit if
// it ever feels laggy or jumpy in practice (see DESIGN.md open risks).
Vector2D                                       g_lastDragPos{};
std::chrono::steady_clock::time_point          g_lastDragCall{};
constexpr std::chrono::milliseconds            DRAG_GAP_RESET{150};

SDispatchResult dispatchPanDrag(std::string) {
    const auto now = std::chrono::steady_clock::now();
    const auto pos = g_pInputManager->getMouseCoordsInternal();

    const bool freshDrag = (now - g_lastDragCall) > DRAG_GAP_RESET;

    if (!freshDrag) {
        const double scale = std::max(0.0001, RenderHook::state().currentScale());
        RenderHook::state().panBy({
            .x = (g_lastDragPos.x - pos.x) / scale,
            .y = (g_lastDragPos.y - pos.y) / scale,
        });
    }

    g_lastDragPos  = pos;
    g_lastDragCall = now;
    return {};
}

SDispatchResult dispatchReset(std::string) {
    RenderHook::state().reset();
    return {};
}
}

void Dispatchers::registerAll(HANDLE handle) {
    HyprlandAPI::addDispatcherV2(handle, "toggle", dispatchToggle);
    HyprlandAPI::addDispatcherV2(handle, "zoom", dispatchZoom);
    HyprlandAPI::addDispatcherV2(handle, "pan", dispatchPan);
    HyprlandAPI::addDispatcherV2(handle, "panDrag", dispatchPanDrag);
    HyprlandAPI::addDispatcherV2(handle, "reset", dispatchReset);
}
