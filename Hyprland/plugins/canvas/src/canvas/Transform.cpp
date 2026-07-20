/* &desc: "Transform implementation -- grid-cell origin combined with global canvas pan/zoom." */
#include "Transform.hpp"

SRenderTransform Transform::computeWorkspaceTransform(const CCanvasState& state, const CanvasVec2& monitorSizePx, const GridSlot& slot) {
    const double scale = state.currentScale();
    const auto   pan   = state.currentPan();

    // This workspace's top-left in canvas space, before pan/zoom is applied.
    const CanvasVec2 gridOrigin{
        .x = slot.col * monitorSizePx.x,
        .y = slot.row * monitorSizePx.y,
    };

    SRenderTransform out;
    out.scale       = static_cast<float>(scale);
    out.translate.x = (gridOrigin.x - pan.x) * scale;
    out.translate.y = (gridOrigin.y - pan.y) * scale;

    return out;
}
