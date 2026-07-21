/* &desc: "Transform implementation -- per-window camera translate/scale and its screen<->canvas inverse." */
#include "Transform.hpp"

// A window's real box gets scale()'d then translate()'d (in that insertion
// order -- see RenderHook.cpp for why order matters). After scale: realPos *
// scale. We want that to land on screenPos = (canvasPos - pan) * scale. So:
// translate = screenPos - realPos*scale = (canvasPos - pan)*scale - realPos*scale
//           = (canvasPos - pan - realPos) * scale
SRenderTransform Transform::windowTransform(const CCanvasState& state, const CanvasVec2& canvasPos, const CanvasVec2& realPos) {
    const double scale = state.currentScale();
    const auto   pan   = state.currentPan();

    SRenderTransform out;
    out.scale       = static_cast<float>(scale);
    out.translate.x = (canvasPos.x - pan.x - realPos.x) * scale;
    out.translate.y = (canvasPos.y - pan.y - realPos.y) * scale;
    return out;
}

// screenPos = (canvasPos - pan) * scale  =>  canvasPos = screenPos / scale + pan
CanvasVec2 Transform::screenToCanvas(const CCanvasState& state, const CanvasVec2& screenPos) {
    const double scale = state.currentScale();
    const auto   pan   = state.currentPan();

    return CanvasVec2{
        .x = screenPos.x / scale + pan.x,
        .y = screenPos.y / scale + pan.y,
    };
}
