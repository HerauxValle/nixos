// &desc: "plugin entry points -- thin glue, all real work happens in HyprlandHooks.cpp"
#include "HyprlandHooks.hpp"

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (!CanvasHooks::init(handle))
        throw std::runtime_error("canvas: hook installation failed, see notification/log");

    return {"canvas", "ComfyUI-style infinite pan/zoom canvas: Meta+Shift+C toggle, Meta+Shift+Scroll zoom, Meta+Shift+RMB drag", "HerauxValle", "0.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    CanvasHooks::shutdown();
}
