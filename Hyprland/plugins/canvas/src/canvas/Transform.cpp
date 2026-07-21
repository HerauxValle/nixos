/* &desc: "Transform implementation -- camera translate/scale and its screen<->canvas inverse." */
#include "Transform.hpp"

// screenPos = (canvasPos - pan) * scale  =>  canvasPos = screenPos / scale + pan
SRenderTransform Transform::cameraTransform(const CCanvasState& state) {
    const double scale = state.currentScale();
    const auto   pan   = state.currentPan();

    SRenderTransform out;
    out.scale       = static_cast<float>(scale);
    out.translate.x = -pan.x * scale;
    out.translate.y = -pan.y * scale;
    return out;
}

CanvasVec2 Transform::screenToCanvas(const CCanvasState& state, const CanvasVec2& screenPos) {
    const double scale = state.currentScale();
    const auto   pan   = state.currentPan();

    return CanvasVec2{
        .x = screenPos.x / scale + pan.x,
        .y = screenPos.y / scale + pan.y,
    };
}
