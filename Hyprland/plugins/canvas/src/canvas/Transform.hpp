/* &desc: "Pure math: canvas state + monitor size + grid slot -> render translate/scale." */
#pragma once

#include "CanvasState.hpp"
#include "Grid.hpp"

struct SRenderTransform {
    CanvasVec2 translate{};
    float      scale = 1.0f;
};

namespace Transform {
    // Where should the workspace occupying `slot` in the grid render on
    // screen, given the live pan/zoom state and this monitor's pixel size?
    // Each grid cell is exactly one monitor-size wide/tall in canvas space
    // (workspaces tile like a wall of monitor-sized panels); the canvas's
    // own scale/pan then zooms/pans that whole wall. Assumes canvas mode is
    // active -- callers in the hypr/ layer decide whether to use this at
    // all versus rendering normally.
    SRenderTransform computeWorkspaceTransform(const CCanvasState& state, const CanvasVec2& monitorSizePx, const GridSlot& slot);
}
