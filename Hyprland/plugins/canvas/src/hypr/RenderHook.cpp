/* &desc: "RenderHook implementation -- hooks IHyprRenderer::renderAllClientsForWorkspace only." */
#include "RenderHook.hpp"

#include "../canvas/Transform.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/helpers/Monitor.hpp>
#include <hyprland/src/desktop/Workspace.hpp>

#include <chrono>
#include <unordered_map>

// Traced against Hyprland 0.55.4's real src/render/Renderer.cpp (not just the
// header) before writing this: renderAllClientsForWorkspace has exactly one
// call site in the whole compositor (IHyprRenderer::renderWorkspace, itself
// called once per monitor per frame from renderMonitor, always for that
// monitor's own m_activeWorkspace). Its translate/scale work by pushing a
// render-pass-wide modifier that's popped again before it returns
// (SRenderModifData / CRendererHintsPassElement in Renderer.cpp) -- exactly
// the mechanism this hook rides, just parameterized by a per-workspace
// camera instead of the identity transform Hyprland normally passes.
//
// Earlier design tried making one workspace's render call fan out into many
// (one per grid slot) to show multiple workspaces at once. Confirmed via
// screenshot + reading shouldRenderWindow() in the real source: a window
// only renders if its *own* workspace is genuinely the one switched-to
// (CWorkspace::isVisible(), a real compositor state flag) -- not whichever
// workspace happens to get passed into this call. So calls for any
// workspace other than the monitor's real active one render nothing (or
// worse, corrupt adjacent render-pass state), no matter what translate/
// scale is used. Dropped that model entirely: canvas mode is now a
// per-workspace *camera* (own pan/zoom, own infinite coordinate space for
// its own floating windows), never touching any other workspace's render at
// all -- see DESIGN.md.
using origRenderAllClientsForWorkspace = void (*)(Render::IHyprRenderer*, PHLMONITOR, PHLWORKSPACE, const Time::steady_tp&, const Vector2D&, const float&);

namespace {
CFunctionHook*                          g_pHook = nullptr;
std::unordered_map<WORKSPACEID, CCanvasState> g_states;
std::unordered_map<WORKSPACEID, Time::steady_tp> g_lastTick;

void hkRenderAllClientsForWorkspace(Render::IHyprRenderer* thisptr, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspace, const Time::steady_tp& time, const Vector2D& translate,
                                     const float& scale) {
    const auto ORIGINAL = (origRenderAllClientsForWorkspace)g_pHook->m_original;

    if (!pWorkspace) {
        (*ORIGINAL)(thisptr, pMonitor, pWorkspace, time, translate, scale);
        return;
    }

    const auto it = g_states.find(pWorkspace->m_id);
    if (it == g_states.end() || !it->second.active()) {
        // Not a canvas workspace right now -- pass through whatever
        // translate/scale Hyprland itself wanted (identity, normally),
        // untouched. Don't assume it's always {0,0}/1.0 -- something else
        // (e.g. the built-in cursor zoom accessibility feature) could
        // legitimately already be using this same parameter.
        (*ORIGINAL)(thisptr, pMonitor, pWorkspace, time, translate, scale);
        return;
    }

    auto& state = it->second;

    auto&      lastTick = g_lastTick[pWorkspace->m_id];
    if (lastTick.time_since_epoch().count() != 0)
        state.tick(std::chrono::duration<double>(time - lastTick).count());
    lastTick = time;

    const auto xf = Transform::cameraTransform(state);
    (*ORIGINAL)(thisptr, pMonitor, pWorkspace, time, Vector2D{xf.translate.x, xf.translate.y}, xf.scale);

    g_pHyprRenderer->damageMonitor(pMonitor);
}
}

bool RenderHook::install(HANDLE handle) {
    const auto FNS = HyprlandAPI::findFunctionsByName(handle, "renderAllClientsForWorkspace");

    for (auto& fn : FNS) {
        if (!fn.demangled.contains("IHyprRenderer"))
            continue;

        g_pHook = HyprlandAPI::createFunctionHook(handle, fn.address, (void*)::hkRenderAllClientsForWorkspace);
        break;
    }

    if (!g_pHook)
        return false;

    return g_pHook->hook();
}

void RenderHook::uninstall() {
    if (g_pHook)
        g_pHook->unhook();
}

CCanvasState& RenderHook::stateFor(WORKSPACEID id) {
    return g_states[id];
}

void RenderHook::forgetWorkspace(WORKSPACEID id) {
    g_states.erase(id);
    g_lastTick.erase(id);
}
