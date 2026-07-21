/* &desc: "RenderHook implementation -- hooks IHyprRenderer::renderWindow (per-window transform) and shouldRenderWindow (force-visible safety net)." */
#include "RenderHook.hpp"

#include "../canvas/Transform.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/types.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <hyprland/src/helpers/Monitor.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/desktop/view/Window.hpp>

#include <chrono>
#include <unordered_map>

// Root cause, found by tracing the real source (not guessed): encoding a
// window's canvas-space position by writing it into the window's *real*
// Hyprland position (this plugin's original approach, via
// Config::Actions::move) runs straight into CWindow::visibleOnMonitor()
// (desktop/view/Window.cpp) -- a native gate, checked by shouldRenderWindow()
// *before* any plugin render hook runs, that compares a window's real,
// untransformed position against the monitor's real rectangle. Pan far
// enough and a window's real position lands outside the monitor's real
// bounds; Hyprland drops it from that monitor's render pass entirely,
// regardless of what a render-time transform would have done. Forcing
// shouldRenderWindow() true and expanding CRenderPass::render()'s damage
// region (both tried, both confirmed installed and firing correctly via
// direct instrumentation) still weren't sufficient on their own -- something
// further downstream continued to block the actual draw even with both of
// those gates demonstrably bypassed.
//
// The fix that removes the problem at its root instead of fighting each of
// its symptoms one at a time: never write canvas position into real
// position at all. Each window's canvas-space position lives in
// g_canvasPos, entirely decoupled from wherever Hyprland's own default
// floating placement put its *real* box -- which now stays wherever
// Hyprland naturally puts new floating windows, always comfortably
// on-monitor, so visibleOnMonitor has no reason to ever exclude it in the
// first place. This hook computes a *per-window* transform -- translate/
// scale from the difference between where a window actually is (real) and
// where it should visually appear (canvas position, camera pan/scale) --
// instead of relying on a window's real position ever needing to differ
// from another window's by more than they naturally would.
using origRenderWindow = void (*)(Render::IHyprRenderer*, PHLWINDOW, PHLMONITOR, const Time::steady_tp&, bool, Render::eRenderPassMode, bool, bool);
using origShouldRender = bool (*)(Render::IHyprRenderer*, PHLWINDOW, PHLMONITOR);

namespace {
CFunctionHook*                                   g_pRenderWindowHook = nullptr;
CFunctionHook*                                   g_pShouldRenderHook = nullptr;
std::unordered_map<WORKSPACEID, CCanvasState>    g_states;
std::unordered_map<WORKSPACEID, Time::steady_tp> g_lastTick;
std::unordered_map<Desktop::View::CWindow*, CanvasVec2> g_canvasPos;

bool workspaceCanvasActive(WORKSPACEID id) {
    const auto it = g_states.find(id);
    return it != g_states.end() && it->second.active();
}

void tickIfNeeded(CCanvasState& state, WORKSPACEID id, const Time::steady_tp& time) {
    auto& lastTick = g_lastTick[id];
    if (lastTick.time_since_epoch().count() != 0)
        state.tick(std::chrono::duration<double>(time - lastTick).count());
    lastTick = time;
    // renderWindow fires once per window, all sharing the same frame's
    // `time` -- every call after the first within a frame sees dt == 0
    // above (lastTick was just set to this same `time`), a harmless no-op
    // ease step. No separate "already ticked this frame" guard needed.
}

// Safety net alongside the per-window transform below: even though real
// position now stays normal/on-monitor (so visibleOnMonitor should already
// pass on its own), force it true explicitly for any window on a
// canvas-active workspace's own monitor, removing that gate as a variable
// entirely rather than trusting it implicitly.
bool hkShouldRenderWindow(Render::IHyprRenderer* thisptr, PHLWINDOW pWindow, PHLMONITOR pMonitor) {
    if (pWindow && pMonitor && pWindow->m_workspace && pWindow->m_workspace->m_monitor.lock() == pMonitor && workspaceCanvasActive(pWindow->m_workspace->m_id))
        return true;

    return ((origShouldRender)g_pShouldRenderHook->m_original)(thisptr, pWindow, pMonitor);
}

void hkRenderWindow(Render::IHyprRenderer* thisptr, PHLWINDOW pWindow, PHLMONITOR pMonitor, const Time::steady_tp& time, bool decorate, Render::eRenderPassMode mode, bool ignorePosition,
                    bool standalone) {
    const auto original = (origRenderWindow)g_pRenderWindowHook->m_original;

    if (!pWindow || !pMonitor || !pWindow->m_workspace) {
        (*original)(thisptr, pWindow, pMonitor, time, decorate, mode, ignorePosition, standalone);
        return;
    }

    const auto it = g_states.find(pWindow->m_workspace->m_id);
    // Only transform when this window is rendering on its *own* workspace's
    // owning monitor -- leaves the rare "floating window visible on a
    // neighboring monitor" case (a different, non-canvas render context)
    // untouched.
    if (it == g_states.end() || !it->second.active() || pWindow->m_workspace->m_monitor.lock() != pMonitor) {
        (*original)(thisptr, pWindow, pMonitor, time, decorate, mode, ignorePosition, standalone);
        return;
    }

    auto& state = it->second;
    tickIfNeeded(state, pWindow->m_workspace->m_id, time);

    const CanvasVec2 realMonRelative{pWindow->m_realPosition->value().x - pMonitor->m_position.x, pWindow->m_realPosition->value().y - pMonitor->m_position.y};

    auto mapIt = g_canvasPos.find(pWindow.get());
    if (mapIt == g_canvasPos.end())
        mapIt = g_canvasPos.emplace(pWindow.get(), Transform::screenToCanvas(state, realMonRelative)).first;

    const auto xf = Transform::windowTransform(state, mapIt->second, realMonRelative);

    // Order matters: applyToBox applies modifs in insertion order
    // (box.scale() then box.translate(), chained) -- windowTransform's
    // translate is derived assuming scale lands first, so push scale
    // before translate here to match.
    Render::SRenderModifData modif;
    if (xf.scale != 1.f)
        modif.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_SCALE, xf.scale);
    if (xf.translate.x != 0.0 || xf.translate.y != 0.0)
        modif.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_TRANSLATE, Vector2D{xf.translate.x, xf.translate.y});

    const bool hasModif = !modif.modifs.empty();
    if (hasModif)
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{modif}));

    (*original)(thisptr, pWindow, pMonitor, time, decorate, mode, ignorePosition, standalone);

    if (hasModif)
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{Render::SRenderModifData{}}));

    g_pHyprRenderer->damageMonitor(pMonitor);
}

bool hookOne(HANDLE handle, const char* fnName, const char* classHint, CFunctionHook*& slot, void* trampoline) {
    const auto FNS = HyprlandAPI::findFunctionsByName(handle, fnName);
    for (auto& fn : FNS) {
        if (!fn.demangled.contains(classHint))
            continue;
        slot = HyprlandAPI::createFunctionHook(handle, fn.address, trampoline);
        break;
    }
    return slot && slot->hook();
}
}

bool RenderHook::install(HANDLE handle) {
    const bool a = hookOne(handle, "renderWindow", "IHyprRenderer", g_pRenderWindowHook, (void*)::hkRenderWindow);
    // shouldRenderWindow is overloaded (PHLWINDOW) and (PHLWINDOW, PHLMONITOR)
    // -- "Monitor" in the demangled signature picks the two-arg one we need.
    const bool b = hookOne(handle, "shouldRenderWindow", "Monitor", g_pShouldRenderHook, (void*)::hkShouldRenderWindow);
    return a && b;
}

void RenderHook::uninstall() {
    if (g_pRenderWindowHook)
        g_pRenderWindowHook->unhook();
    if (g_pShouldRenderHook)
        g_pShouldRenderHook->unhook();
}

CCanvasState& RenderHook::stateFor(WORKSPACEID id) {
    return g_states[id];
}

void RenderHook::forgetWorkspace(WORKSPACEID id) {
    g_states.erase(id);
    g_lastTick.erase(id);
}

void RenderHook::setCanvasPos(PHLWINDOW window, const CanvasVec2& pos) {
    if (window)
        g_canvasPos[window.get()] = pos;
}

std::optional<CanvasVec2> RenderHook::canvasPosFor(PHLWINDOW window) {
    if (!window)
        return std::nullopt;
    const auto it = g_canvasPos.find(window.get());
    return it == g_canvasPos.end() ? std::nullopt : std::optional{it->second};
}

void RenderHook::forgetWindow(PHLWINDOW window) {
    if (window)
        g_canvasPos.erase(window.get());
}
