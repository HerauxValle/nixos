/* &desc: "The plugin's single fragile hook: renderAllClientsForWorkspace. See DESIGN.md." */
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

    // The shared canvas state the hook reads every frame. Owned here so
    // Dispatchers.cpp (which mutates it) and the hook (which reads it) share
    // one instance without main.cpp needing to wire up a singleton itself.
    CCanvasState& state();
}
