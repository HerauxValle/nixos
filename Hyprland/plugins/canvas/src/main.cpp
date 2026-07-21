/* &desc: "Plugin entrypoint -- pluginAPIVersion/pluginInit/pluginExit. Wiring only, no logic lives here." */
#include <hyprland/src/plugins/PluginAPI.hpp>

#include "hypr/VersionGuard.hpp"
#include "hypr/RenderHook.hpp"
#include "hypr/Dispatchers.hpp"
#include "hypr/WindowPlacement.hpp"

// Do NOT change this function -- required verbatim by every Hyprland plugin.
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (checkHyprlandVersion(handle)) {
        if (!RenderHook::install(handle))
            HyprlandAPI::addNotification(handle, "[canvas] Disabled: couldn't find renderMonitor/renderLayer/visibleOnMonitor/renderWindow to hook -- dispatchers still active",
                                          CHyprColor{1.0, 0.2, 0.2, 1.0},
                                          6000);
    }

    Dispatchers::registerAll(handle);
    WindowPlacement::registerListeners(handle);

    return {"canvas", "Infinite canvas per workspace: floating windows placed anywhere in an unbounded space, pan/zoom to navigate", "herauxvalle", "0.1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    RenderHook::uninstall();
}
