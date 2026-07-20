/* &desc: "Version-mismatch guard for the canvas plugin -- see DESIGN.md's fragility ledger." */
#pragma once

#include <hyprland/src/plugins/PluginAPI.hpp>

// Compares this plugin's compiled-in Hyprland ABI hash against the running
// server's, via the __hyprland_api_get_hash()/__hyprland_api_get_client_hash()
// pair every Hyprland plugin gets for free (see PluginAPI.hpp). Returns true
// if it's safe to install the render hooks.
//
// On mismatch: fires a loud, visible HyprlandAPI::addNotification warning and
// returns false. main.cpp then skips RenderHook::install but still registers
// dispatchers, so canvas:* commands don't hard-crash -- a visible "degraded,
// hooks disabled" state rather than either silent misbehavior or refusing to
// load entirely. This is deliberately softer than official plugins' own
// convention (which throw and abort pluginInit on mismatch) -- see DESIGN.md.
bool checkHyprlandVersion(HANDLE handle);
