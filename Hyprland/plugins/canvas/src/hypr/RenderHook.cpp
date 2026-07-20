/* &desc: "RenderHook implementation -- hooks IHyprRenderer::renderAllClientsForWorkspace only." */
#include "RenderHook.hpp"

#include "../canvas/Transform.hpp"
#include "../canvas/Grid.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/helpers/Monitor.hpp>

#include <algorithm>
#include <chrono>
#include <vector>

// Traced against Hyprland 0.55.4's real src/render/Renderer.cpp (not just the
// header) before writing this: renderAllClientsForWorkspace has exactly one
// call site in the whole compositor (IHyprRenderer::renderWorkspace, itself
// called once per monitor per frame from renderMonitor). Its translate/scale
// work by pushing a render-pass-wide modifier that's popped again before it
// returns (SRenderModifData / CRendererHintsPassElement in Renderer.cpp), so
// calling it N times back-to-back for N different workspaces -- each with its
// own translate/scale -- renders each one at its own transformed position
// within the *same*, already-begun render pass. That's the entire multi-
// workspace grid: no second orchestration hook (e.g. renderMonitor) needed,
// simplifying the originally-planned two-hook design down to one. See
// DESIGN.md's fragility ledger for the exact signature this relies on.
using origRenderAllClientsForWorkspace = void (*)(Render::IHyprRenderer*, PHLMONITOR, PHLWORKSPACE, const Time::steady_tp&, const Vector2D&, const float&);

namespace {
CFunctionHook* g_pHook = nullptr;
CCanvasState   g_state;
Time::steady_tp g_lastTick{};
bool            g_wasActive = false; // detects the activation edge, see the fit-on-activate block below

std::vector<PHLWORKSPACE> workspacesOnMonitor(PHLMONITOR pMonitor) {
    std::vector<PHLWORKSPACE> out;
    for (auto& ws : g_pCompositor->getWorkspacesCopy()) {
        if (!ws || ws->m_isSpecialWorkspace)
            continue;
        if (ws->m_monitor.lock() != pMonitor)
            continue;
        out.push_back(ws);
    }
    return out;
}

void hkRenderAllClientsForWorkspace(Render::IHyprRenderer* thisptr, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspace, const Time::steady_tp& time, const Vector2D& translate,
                                     const float& scale) {
    const auto ORIGINAL = (origRenderAllClientsForWorkspace)g_pHook->m_original;

    if (!g_state.active()) {
        g_wasActive = false;
        (*ORIGINAL)(thisptr, pMonitor, pWorkspace, time, translate, scale);
        return;
    }

    // Ease state toward its target once per frame. Multiple monitors each
    // call this once per their own frame, so this may tick more than once
    // per "true" frame on multi-monitor setups -- harmless, just slightly
    // uneven pacing across differently-refreshing monitors, not a bug.
    if (g_lastTick.time_since_epoch().count() != 0)
        g_state.tick(std::chrono::duration<double>(time - g_lastTick).count());
    g_lastTick = time;

    const auto workspaces = workspacesOnMonitor(pMonitor);
    if (workspaces.empty()) {
        (*ORIGINAL)(thisptr, pMonitor, pWorkspace, time, translate, scale);
        return;
    }

    const CanvasVec2 monitorSizePx{pMonitor->m_pixelSize.x, pMonitor->m_pixelSize.y};

    // Toggling active() alone never touched zoom/pan -- scale stayed at 1.0,
    // so grid slots (spaced a full monitor-size apart) didn't overlap the
    // visible viewport at all; only whichever workspace happened to land in
    // the on-screen slot showed anything, usually not the one you were
    // actually looking at. Confirmed live: this produced a stuck blank/gray
    // primary monitor with a 10-workspace grid at scale 1.0. Fix: the instant
    // activation is detected, auto-target a scale that fits the whole grid
    // and center the pan on whichever workspace was active, so canvas mode is
    // immediately coherent instead of requiring a manual zoom-out first.
    if (!g_wasActive) {
        const int cols = Grid::columnsFor(workspaces.size());
        const int rows = (static_cast<int>(workspaces.size()) + cols - 1) / cols;
        g_state.zoomTo(1.0 / static_cast<double>(std::max(cols, rows)));

        for (std::size_t i = 0; i < workspaces.size(); ++i) {
            if (workspaces[i] != pMonitor->m_activeWorkspace)
                continue;
            const auto activeSlot = Grid::slotFor(i, workspaces.size());
            g_state.panTo({.x = activeSlot.col * monitorSizePx.x, .y = activeSlot.row * monitorSizePx.y});
            break;
        }
    }
    g_wasActive = true;

    for (std::size_t i = 0; i < workspaces.size(); ++i) {
        const auto slot = Grid::slotFor(i, workspaces.size());
        const auto xf   = Transform::computeWorkspaceTransform(g_state, monitorSizePx, slot);
        (*ORIGINAL)(thisptr, pMonitor, workspaces[i], time, Vector2D{xf.translate.x, xf.translate.y}, xf.scale);
    }

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

CCanvasState& RenderHook::state() {
    return g_state;
}
