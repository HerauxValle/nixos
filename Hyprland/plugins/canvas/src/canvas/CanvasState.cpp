/* &desc: "CCanvasState implementation -- zoom/pan targets, easing, and scale clamping." */
#include "CanvasState.hpp"

#include <algorithm>

namespace {
constexpr double MIN_SCALE  = 0.15; // furthest zoomed-out
constexpr double MAX_SCALE  = 1.0;  // never zoom in past 1:1 -- that's just normal desktop use
constexpr double EASE_SPEED = 10.0; // higher = snappier; ~100ms to settle at this rate
}

void CCanvasState::activate() {
    m_active = true;
}

void CCanvasState::deactivate() {
    m_active = false;
}

void CCanvasState::toggle() {
    m_active = !m_active;
}

void CCanvasState::zoomBy(double stepMultiplier) {
    zoomTo(m_targetScale * stepMultiplier);
}

void CCanvasState::zoomTo(double absoluteScale) {
    m_targetScale = std::clamp(absoluteScale, MIN_SCALE, MAX_SCALE);
}

void CCanvasState::panBy(const CanvasVec2& deltaCanvasUnits) {
    m_targetPan.x += deltaCanvasUnits.x;
    m_targetPan.y += deltaCanvasUnits.y;
}

void CCanvasState::panTo(const CanvasVec2& pos) {
    m_targetPan = pos;
}

void CCanvasState::reset() {
    m_targetScale = 1.0;
    m_targetPan   = CanvasVec2{};
}

void CCanvasState::tick(double dtSeconds) {
    const double t = std::clamp(dtSeconds * EASE_SPEED, 0.0, 1.0);

    m_scale  = m_scale + (m_targetScale - m_scale) * t;
    m_pan.x  = m_pan.x + (m_targetPan.x - m_pan.x) * t;
    m_pan.y  = m_pan.y + (m_targetPan.y - m_pan.y) * t;
}
