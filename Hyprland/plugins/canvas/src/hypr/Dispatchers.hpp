/* &desc: "Registers the canvas plugin's dispatchers (toggle/zoom/pan/panDrag/reset)." */
#pragma once

#include <hyprland/src/plugins/PluginAPI.hpp>

namespace Dispatchers {
    void registerAll(HANDLE handle);
}
