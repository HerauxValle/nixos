#pragma once
// &desc: "pure pan/zoom/toggle math for the canvas plugin -- zero Hyprland compositor types"

#include <hyprutils/math/Vector2D.hpp>

using namespace Hyprutils::Math;

// This header/impl pair is the "logic" half asked for: it knows nothing about
// CCompositor, CWindow, CMonitor, IPointer, or any other Hyprland compositor
// type. It only models a 2D camera (zoom + pan offset) over an infinite
// "canvas" plane where windows keep their normal Hyprland positions, plus the
// coordinate math to go between that plane and physical monitor pixels.
//
// HyprlandHooks.cpp is the only file that calls into Hyprland's plugin API or
// touches compositor internals; it owns one CCanvasState instance and only
// ever reads/mutates it through these methods. That keeps "what does the
// compositor look like" and "how does the camera behave" independently
// testable/readable, per the requested split.
class CCanvasState {
  public:
    // --- camera state ---
    double   m_zoom   = 1.0;
    Vector2D m_offset = {0, 0}; // canvas-space point shown at physical (0,0)

    // --- interaction state ---
    bool m_active  = false; // Meta+Shift+C toggles this
    bool m_panning = false; // true while Meta+Shift+RMB is held and moving

    // Range picked for a ComfyUI-style canvas: zoom out past 100% to see the
    // whole desktop, or in past 100% to read a small window up close. Purely
    // a feel choice -- widen/narrow freely, nothing else depends on the exact
    // numbers.
    static constexpr double ZOOM_MIN  = 0.1;
    static constexpr double ZOOM_MAX  = 4.0;
    static constexpr double ZOOM_STEP = 1.15; // ~15% per scroll notch

    Vector2D screenToCanvas(const Vector2D& screen) const;
    Vector2D canvasToScreen(const Vector2D& canvas) const;

    // Cursor-anchored zoom: whatever canvas point is under `anchorScreen`
    // stays under the cursor after the zoom (same trick Figma/Maps/ComfyUI
    // use). See CanvasState.cpp for the derivation.
    void applyZoom(double newZoom, const Vector2D& anchorScreen);

    // Meta+Shift+C. Deactivating also resets zoom/offset/panning to identity
    // so "canvas mode off" is bit-for-bit the same as vanilla Hyprland: every
    // hook in HyprlandHooks.cpp gates on m_active alone, so a leftover
    // non-identity camera would otherwise keep nudging rendering/input even
    // while "off".
    void toggle();
};
