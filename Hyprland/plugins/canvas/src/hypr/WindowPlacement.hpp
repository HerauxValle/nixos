/* &desc: "New-window placement for canvas workspaces -- floats new windows at the cursor's canvas position." */
#pragma once

#include <hyprland/src/plugins/PluginAPI.hpp>

namespace WindowPlacement {
    // Subscribes to the stable EventBus (window.open, workspace.removed) --
    // no extra function hook needed for this, unlike the render transform.
    void registerListeners(HANDLE handle);
}
