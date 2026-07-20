/* &desc: "VersionGuard implementation -- __hyprland_api_get_hash() vs __hyprland_api_get_client_hash()." */
#include "VersionGuard.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>

bool checkHyprlandVersion(HANDLE handle) {
    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();

    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(handle, "[canvas] Disabled: built against a different Hyprland version than what's running -- render hooks skipped, dispatchers still active",
                                      CHyprColor{1.0, 0.2, 0.2, 1.0}, 6000);
        return false;
    }

    return true;
}
