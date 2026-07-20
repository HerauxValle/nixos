/* &desc: "Pure math: canvas camera state -> render translate/scale, and the inverse (screen -> canvas coords)." */
#pragma once

#include "CanvasState.hpp"

struct SRenderTransform {
    CanvasVec2 translate{};
    float      scale = 1.0f;
};

namespace Transform {
    // What translate/scale to feed the renderer so this workspace's windows
    // (which live at arbitrary canvas-space coordinates, not bound to one
    // screen's worth of space) appear correctly panned/zoomed on screen.
    SRenderTransform cameraTransform(const CCanvasState& state);

    // Inverse: given a point in screen space (e.g. the live cursor position)
    // and this workspace's camera state, where is that point in canvas
    // space? Used to place new windows where the cursor is instead of at a
    // fixed origin, mirroring how a new ComfyUI node appears near your view.
    CanvasVec2 screenToCanvas(const CCanvasState& state, const CanvasVec2& screenPos);
}
