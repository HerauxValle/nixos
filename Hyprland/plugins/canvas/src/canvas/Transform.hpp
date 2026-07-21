/* &desc: "Pure math: canvas camera state -> render translate/scale, and the inverse (screen -> canvas coords)." */
#pragma once

#include "CanvasState.hpp"

struct SRenderTransform {
    CanvasVec2 translate{};
    float      scale = 1.0f;
};

namespace Transform {
    // Per-window translate/scale: given this workspace's camera state, a
    // window's *canvas-space* position (tracked independently of Hyprland,
    // see RenderHook's g_canvasPos), and that same window's *real* Hyprland
    // position (monitor-relative, wherever Hyprland actually put it -- never
    // written to by this plugin, see DESIGN.md "Decoupling canvas position
    // from real Hyprland position"), what render-modifier translate/scale
    // makes the window's real box land exactly where its canvas position
    // says it should be on screen. Applied per window (RenderHook hooks
    // renderWindow, not a whole-call function), not once for an entire
    // render call -- each window can be an arbitrary distance from its own
    // real position without that distance ever needing to exist in
    // Hyprland's own coordinate space.
    SRenderTransform windowTransform(const CCanvasState& state, const CanvasVec2& canvasPos, const CanvasVec2& realPos);

    // Inverse of the *camera* part of windowTransform: given a point in
    // screen space (e.g. the live cursor position) and this workspace's
    // camera state, where is that point in canvas space? Used to place new
    // windows where the cursor is instead of at a fixed origin (mirroring
    // how a new ComfyUI node appears near your view), and to lazily
    // establish a window's first canvas position from wherever its real
    // position happens to currently put it on screen.
    CanvasVec2 screenToCanvas(const CCanvasState& state, const CanvasVec2& screenPos);
}
