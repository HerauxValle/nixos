/* &desc: "The plugin's fragile hooks: renderWindow (per-window transform), shouldRenderWindow (force-visible safety net). See DESIGN.md." */
#pragma once

#include <optional>

#include <hyprland/src/plugins/PluginAPI.hpp>

#include "../canvas/CanvasState.hpp"

namespace RenderHook {
    // Resolves and installs the hooks. Returns false (and leaves nothing
    // installed) if a target function can't be found -- callers should
    // treat that as "hooks disabled" the same way a version mismatch is
    // treated, not a hard failure.
    bool install(HANDLE handle);
    void uninstall();

    // Each workspace is its own independent infinite canvas (own pan/zoom
    // camera) -- this gets-or-creates the state for a given workspace ID.
    // Shared by the render hook itself, Dispatchers.cpp (mutates it on
    // keybinds), and WindowPlacement.cpp (reads it to place new windows).
    CCanvasState& stateFor(WORKSPACEID id);

    // Drops a workspace's camera state -- called when a workspace is
    // destroyed so the map doesn't grow unbounded over a long session.
    void forgetWorkspace(WORKSPACEID id);

    // A window's canvas-space position, tracked entirely independently of
    // its real Hyprland position. Set explicitly by WindowPlacement when a
    // window is deliberately placed at the cursor's canvas position, or by
    // Dispatchers when committing a position back on toggle-off. The render
    // hook itself lazily derives one (from the window's current real
    // position) the first time it sees a window with no entry yet.
    void setCanvasPos(PHLWINDOW window, const CanvasVec2& pos);

    // Read-only lookup -- nullopt if this window has never been rendered
    // under canvas mode yet.
    std::optional<CanvasVec2> canvasPosFor(PHLWINDOW window);

    // Drops a window's stored canvas position -- called on window destroy
    // and on workspace-move (so it's freshly re-derived relative to
    // whatever camera it lands under next).
    void forgetWindow(PHLWINDOW window);
}
