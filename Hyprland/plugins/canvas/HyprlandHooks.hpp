#pragma once
// &desc: "Hyprland-facing hook layer: CFunctionHook wiring + dispatcher registration, isolated from camera logic"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <memory>
#include "CanvasState.hpp"

// Everything that talks to Hyprland (createFunctionHook, findFunctionsByName,
// addDispatcherV2, or any compositor type) lives in HyprlandHooks.cpp. This
// header only exposes the two lifecycle entry points main.cpp needs, plus the
// globals every hook trampoline in the .cpp needs to reach.
namespace CanvasHooks {
    // Installs the toggle dispatcher and all CFunctionHooks. Returns false if
    // any *required* hook target failed to resolve -- see DESIGN.md for why
    // partial installation is treated as a hard failure rather than degrading
    // gracefully.
    bool init(HANDLE handle);

    // Unhooks everything, in reverse of install order.
    void shutdown();
}

inline std::unique_ptr<CCanvasState> g_pCanvas;
inline HANDLE                        PHANDLE = nullptr;
