/* &desc: "Pure pan/zoom state machine for the canvas plugin -- no Hyprland types, no #includes beyond the standard library." */
#pragma once

struct CanvasVec2 {
    double x = 0.0;
    double y = 0.0;
};

// Owns the canvas viewport: whether it's active, current/target zoom scale,
// current/target pan offset (in canvas units, i.e. before any per-monitor
// scaling), and eases current toward target on every tick() so state
// changes animate instead of snapping. Everything here is plain doubles --
// this class has no idea Hyprland exists.
class CCanvasState {
  public:
    void activate();
    void deactivate();
    void toggle();

    // stepMultiplier > 1 zooms in (e.g. 1.25), < 1 zooms out (e.g. 0.8)
    void zoomBy(double stepMultiplier);
    void zoomTo(double absoluteScale);

    void panBy(const CanvasVec2& deltaCanvasUnits);
    void panTo(const CanvasVec2& pos);

    void reset();

    // Advances current scale/pan toward their targets. dtSeconds is wall
    // time since the last tick; callers decide when/how often to call this
    // (e.g. once per render frame while active).
    void tick(double dtSeconds);

    bool       active() const { return m_active; }
    double     currentScale() const { return m_scale; }
    CanvasVec2 currentPan() const { return m_pan; }

  private:
    double     m_scale       = 1.0;
    double     m_targetScale = 1.0;
    CanvasVec2 m_pan{};
    CanvasVec2 m_targetPan{};
    bool       m_active = false;
};
