/* &desc: "RenderHook implementation -- faked-monitor-scale zoom (renderMonitor/renderLayer), direct visibleOnMonitor force-visible, per-window renderWindow translate for pan." */
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

// Session history (why this file looks the way it does -- read this before
// changing any of these four hooks):
//
// 1st design: hooked the whole-call renderAllClientsForWorkspace, pushing a
// translate/scale SRenderModifData around it. Abandoned -- that also
// zoomed background/layer-shell surfaces (wallpaper, and crucially
// TOP/OVERLAY-layer bars: a real quickshell bar zoomed along with windows,
// confirmed live).
//
// 2nd design: narrowed the hook to renderWorkspaceWindows/Fullscreen
// (windows only, no layers) -- fixed the bar-zooming bug, and a real
// render-modifier insertion-order bug alongside it (SCALE must be pushed
// before TRANSLATE, not after -- see Transform.cpp). Placed a window's
// canvas position by writing it straight into its *real* Hyprland position
// (Config::Actions::move). Worked for small pans, but panning a window's
// real position far enough from the monitor made it invisible: confirmed
// via hand-derived math *and* live ground-truth logging that
// CWindow::visibleOnMonitor() (checked by shouldRenderWindow(), called
// *before* any of our hooks run) gates on a window's real, untransformed
// position against the monitor's real rectangle.
//
// 3rd design: decoupled canvas position from real position (a window's
// canvas coordinate lives in g_canvasPos here, its real Hyprland position
// stays wherever Hyprland's own default floating placement put it -- always
// on-monitor) and switched to hooking renderWindow per-window instead of
// the whole-call functions, computing a translate+scale SRenderModifData
// per window from the difference between its real and canvas positions.
// Also added a shouldRenderWindow(window,monitor) hook forcing it true for
// canvas-active workspaces, and a CRenderPass::render() hook expanding the
// damage argument to the canvas-space rect currently visible on screen.
// Both of those were confirmed *installed and firing correctly* via direct
// ground-truth logging (per-frame: real position, computed viewport box,
// whether the real position falls inside it -- PASS for every window,
// every frame) -- and window content still did not render. Traced the
// entire call chain by hand (renderWorkspaceWindows -> the floating-window
// pass -> renderWindow -> drawSurface -> renderTextureInternal) without
// finding a further blocking condition. Root cause never fully identified
// for that specific combination of hooks; abandoned rather than keep
// guessing at a fourth gate.
//
// 4th (current) design, after actually reading a real, working, maintained
// reference plugin's source (dawsers/hyprscroller's overview.cpp) instead
// of re-deriving from scratch: hyprscroller hits this same "windows outside
// the viewport need to render" problem for its scrolling-tape layout, and
// solves it with a *different* pair of techniques than anything tried
// above:
//   - Hooks CWindow::visibleOnMonitor(PHLMONITOR) *directly* -- not the
//     shouldRenderWindow(window,monitor) wrapper around it. Blanket-forcing
//     shouldRenderWindow's own return value (2nd/3rd design) skips whatever
//     *else* that wrapper's other branches normally do; forcing just the
//     one real gate it calls internally is narrower and leaves the rest of
//     its logic (special-workspace handling, etc.) untouched.
//   - Fakes zoom by temporarily multiplying the *monitor's own* m_scale
//     around the render call (save it, multiply, call the real
//     renderMonitor, restore it) -- instead of injecting a custom
//     SRenderModifData scale. This is the actual insight: m_scale is the
//     same property Hyprland uses everywhere for real HiDPI display
//     scaling, so borders, blur, damage/simplify, shadows -- everything --
//     already correctly respects it natively, because it's core,469
//     pervasively-tested functionality. SRenderModifData's renderModif is
//     exactly the mechanism that decorations/blur/damage do *not* fully
//     respect (confirmed the hard way, at length, in the 2nd/3rd designs
//     above) -- impersonating a real display-scale change sidesteps that
//     whole class of bug instead of chasing each incomplete code path.
//   - Separately hooks renderLayer to *undo* the faked scale just for
//     layer-shell surfaces (background/bars), matching this plugin's own
//     already-established constraint that only window content should zoom.
//
// Pan (translate) still uses this plugin's own per-window renderWindow hook
// and canvas-position bookkeeping from the 3rd design -- hyprscroller's
// overview mode has no pan (it's a fixed-viewpoint zoomed-out overview of
// the whole tape), so it doesn't have to solve that part. Only the
// *translate* SRenderModifData still gets pushed there now, not scale --
// pushing both would double-scale, since the monitor's real m_scale has
// already scaled everything (including a window's real position) natively
// before our per-window modifier ever runs. Not yet live-verified this
// session -- see DESIGN.md's "Not yet done" / status section for exactly
// what was confirmed vs. still needs a fresh check.
using origRenderMonitor    = void (*)(Render::IHyprRenderer*, PHLMONITOR, bool);
using origRenderLayer      = void (*)(Render::IHyprRenderer*, PHLLS, PHLMONITOR, const Time::steady_tp&, bool, bool);
using origVisibleOnMonitor = bool (*)(Desktop::View::CWindow*, PHLMONITOR);
using origRenderWindow     = void (*)(Render::IHyprRenderer*, PHLWINDOW, PHLMONITOR, const Time::steady_tp&, bool, Render::eRenderPassMode, bool, bool);

namespace {
CFunctionHook*                                          g_pRenderMonitorHook    = nullptr;
CFunctionHook*                                          g_pRenderLayerHook      = nullptr;
CFunctionHook*                                          g_pVisibleOnMonitorHook = nullptr;
CFunctionHook*                                          g_pRenderWindowHook     = nullptr;
std::unordered_map<WORKSPACEID, CCanvasState>           g_states;
std::unordered_map<WORKSPACEID, Time::steady_tp>        g_lastTick;
std::unordered_map<Desktop::View::CWindow*, CanvasVec2> g_canvasPos;

CCanvasState* activeStateForMonitor(PHLMONITOR pMonitor) {
    if (!pMonitor || !pMonitor->m_activeWorkspace)
        return nullptr;
    const auto it = g_states.find(pMonitor->m_activeWorkspace->m_id);
    if (it == g_states.end() || !it->second.active())
        return nullptr;
    return &it->second;
}

void tickIfNeeded(CCanvasState& state, WORKSPACEID id, const Time::steady_tp& time) {
    auto& lastTick = g_lastTick[id];
    if (lastTick.time_since_epoch().count() != 0)
        state.tick(std::chrono::duration<double>(time - lastTick).count());
    lastTick = time;
}

// Zoom: fake the monitor's own scale for the whole frame. Ticks the camera
// here (once per monitor per frame) rather than in hkRenderWindow (which
// fires once per window) since this is now the single per-frame entry
// point we hook.
void hkRenderMonitor(Render::IHyprRenderer* thisptr, PHLMONITOR pMonitor, bool commit) {
    const auto original = (origRenderMonitor)g_pRenderMonitorHook->m_original;

    const auto it = pMonitor && pMonitor->m_activeWorkspace ? g_states.find(pMonitor->m_activeWorkspace->m_id) : g_states.end();
    if (it == g_states.end() || !it->second.active()) {
        (*original)(thisptr, pMonitor, commit);
        return;
    }

    auto& state = it->second;
    tickIfNeeded(state, pMonitor->m_activeWorkspace->m_id, Time::steadyNow());

    const float real = pMonitor->m_scale;
    pMonitor->m_scale = real * static_cast<float>(state.currentScale());
    (*original)(thisptr, pMonitor, commit);
    pMonitor->m_scale = real;

    g_pHyprRenderer->damageMonitor(pMonitor);
}

// Undo the faked scale just for layer-shell surfaces (background, bars) --
// only window content should zoom, matching this plugin's whole reason for
// narrowing away from the original whole-call hook in the first place.
void hkRenderLayer(Render::IHyprRenderer* thisptr, PHLLS pLayer, PHLMONITOR pMonitor, const Time::steady_tp& time, bool popups, bool lockscreen) {
    const auto original = (origRenderLayer)g_pRenderLayerHook->m_original;

    auto* state = activeStateForMonitor(pMonitor);
    if (!state) {
        (*original)(thisptr, pLayer, pMonitor, time, popups, lockscreen);
        return;
    }

    const float faked = pMonitor->m_scale;
    pMonitor->m_scale = faked / static_cast<float>(state->currentScale());
    (*original)(thisptr, pLayer, pMonitor, time, popups, lockscreen);
    pMonitor->m_scale = faked;
}

// The actual fix for "windows outside the viewport must still render":
// hooks the one real gate directly instead of its wrapper (see the file
// comment above for why that's different from this plugin's earlier
// attempts). Real position no longer matters for whether a window on a
// canvas-active workspace gets considered for rendering on its own
// monitor at all.
bool hkVisibleOnMonitor(Desktop::View::CWindow* thisptr, PHLMONITOR pMonitor) {
    if (thisptr && pMonitor && thisptr->m_workspace && thisptr->m_workspace->m_monitor.lock() == pMonitor) {
        const auto it = g_states.find(thisptr->m_workspace->m_id);
        if (it != g_states.end() && it->second.active())
            return true;
    }

    return ((origVisibleOnMonitor)g_pVisibleOnMonitorHook->m_original)(thisptr, pMonitor);
}

// Pan only now (see file comment -- zoom is the monitor-scale fake above,
// pushing scale here too would double it).
void hkRenderWindow(Render::IHyprRenderer* thisptr, PHLWINDOW pWindow, PHLMONITOR pMonitor, const Time::steady_tp& time, bool decorate, Render::eRenderPassMode mode, bool ignorePosition,
                    bool standalone) {
    const auto original = (origRenderWindow)g_pRenderWindowHook->m_original;

    if (!pWindow || !pMonitor || !pWindow->m_workspace) {
        (*original)(thisptr, pWindow, pMonitor, time, decorate, mode, ignorePosition, standalone);
        return;
    }

    const auto it = g_states.find(pWindow->m_workspace->m_id);
    if (it == g_states.end() || !it->second.active() || pWindow->m_workspace->m_monitor.lock() != pMonitor) {
        (*original)(thisptr, pWindow, pMonitor, time, decorate, mode, ignorePosition, standalone);
        return;
    }

    auto& state = it->second;

    const CanvasVec2 realMonRelative{pWindow->m_realPosition->value().x - pMonitor->m_position.x, pWindow->m_realPosition->value().y - pMonitor->m_position.y};

    auto mapIt = g_canvasPos.find(pWindow.get());
    if (mapIt == g_canvasPos.end())
        mapIt = g_canvasPos.emplace(pWindow.get(), Transform::screenToCanvas(state, realMonRelative)).first;

    // (canvasPos - pan - realPos) * scale -- same derivation as before, see
    // Transform.cpp. Only ever pushed as translate now; scale comes from
    // the monitor-scale fake in hkRenderMonitor instead.
    const auto  xf = Transform::windowTransform(state, mapIt->second, realMonRelative);
    const bool  hasTranslate = xf.translate.x != 0.0 || xf.translate.y != 0.0;

    if (hasTranslate) {
        Render::SRenderModifData modif;
        modif.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_TRANSLATE, Vector2D{xf.translate.x, xf.translate.y});
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{modif}));
    }

    (*original)(thisptr, pWindow, pMonitor, time, decorate, mode, ignorePosition, standalone);

    if (hasTranslate)
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{Render::SRenderModifData{}}));
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
    const bool a = hookOne(handle, "renderMonitor", "IHyprRenderer", g_pRenderMonitorHook, (void*)::hkRenderMonitor);
    const bool b = hookOne(handle, "renderLayer", "IHyprRenderer", g_pRenderLayerHook, (void*)::hkRenderLayer);
    // visibleOnMonitor: a member of Desktop::View::CWindow in this
    // Hyprland version (not bare CWindow -- see main history in
    // Dispatchers.cpp etc. for other places this namespacing bit us).
    const bool c = hookOne(handle, "visibleOnMonitor", "CWindow", g_pVisibleOnMonitorHook, (void*)::hkVisibleOnMonitor);
    const bool d = hookOne(handle, "renderWindow", "IHyprRenderer", g_pRenderWindowHook, (void*)::hkRenderWindow);
    return a && b && c && d;
}

void RenderHook::uninstall() {
    if (g_pRenderMonitorHook)
        g_pRenderMonitorHook->unhook();
    if (g_pRenderLayerHook)
        g_pRenderLayerHook->unhook();
    if (g_pVisibleOnMonitorHook)
        g_pVisibleOnMonitorHook->unhook();
    if (g_pRenderWindowHook)
        g_pRenderWindowHook->unhook();
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
