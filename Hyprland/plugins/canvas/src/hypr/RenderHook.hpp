/* &desc: "The plugin's fragile hooks: renderWorkspaceWindows/renderWorkspaceWindowsFullscreen. See DESIGN.md." */
#pragma once

#include <hyprland/src/plugins/PluginAPI.hpp>

#include "../canvas/CanvasState.hpp"

namespace RenderHook {
    // Resolves and installs the hook. Returns false (and leaves nothing
    // installed) if the target function can't be found -- callers should
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
}
