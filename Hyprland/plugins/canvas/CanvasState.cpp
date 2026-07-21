// &desc: "coordinate math implementation for CCanvasState"
#include "CanvasState.hpp"

#include <algorithm>

Vector2D CCanvasState::screenToCanvas(const Vector2D& screen) const {
    return m_offset + screen / m_zoom;
}

Vector2D CCanvasState::canvasToScreen(const Vector2D& canvas) const {
    return (canvas - m_offset) * m_zoom;
}

void CCanvasState::applyZoom(double newZoom, const Vector2D& anchorScreen) {
    // 1. What canvas point is currently under the cursor?
    const Vector2D anchorCanvas = screenToCanvas(anchorScreen);

    // 2. Apply the new zoom.
    m_zoom = std::clamp(newZoom, ZOOM_MIN, ZOOM_MAX);

    // 3. Solve offset so that same canvas point is still under the cursor:
    //    anchorScreen == (anchorCanvas - offset) * zoom
    // => offset == anchorCanvas - anchorScreen / zoom
    m_offset = anchorCanvas - anchorScreen / m_zoom;
}

void CCanvasState::toggle() {
    m_active = !m_active;
    if (!m_active) {
        m_zoom    = 1.0;
        m_offset  = {0, 0};
        m_panning = false;
    }
}
