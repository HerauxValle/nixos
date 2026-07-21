/* &desc: "RenderHook implementation -- hooks renderWorkspaceWindows(Fullscreen) for the transform, shouldRenderWindow + CRenderPass::render to stop Hyprland culling panned-off-monitor windows." */
#include "RenderHook.hpp"

#include "../canvas/Transform.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/types.hpp>
#include <hyprland/src/render/pass/Pass.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <hyprland/src/helpers/Monitor.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/desktop/view/Window.hpp>

#include <chrono>
#include <fstream>
#include <unordered_map>

#include <hyprland/src/Compositor.hpp>

// First attempt hooked renderAllClientsForWorkspace and pushed the
// translate/scale modifier around the *entire* call -- which also wraps
// that function's own background/layer-shell rendering (wallpaper, and
// crucially bars/panels in the TOP/OVERLAY layers, confirmed live: a
// quickshell bar was zooming along with the windows). Traced the real
// Renderer.cpp: renderAllClientsForWorkspace calls exactly one of
// renderWorkspaceWindows/renderWorkspaceWindowsFullscreen to draw *just* the
// windows (tiled/floating/pinned, no layers), sandwiched between its own
// background+bottom-layer rendering (before) and top+overlay-layer
// rendering (after) -- both untouched by our hook now. Hooking these two
// narrower functions instead and pushing the modifier only around them
// scopes the transform to window content exclusively, exactly matching
// Hyprland's own push/pop pattern (SRenderModifData via
// CRendererHintsPassElement) but scoped tighter. Two hooks instead of one,
// but each is narrower and the result is more correct.
using origRenderWorkspaceWindows = void (*)(Render::IHyprRenderer*, PHLMONITOR, PHLWORKSPACE, const Time::steady_tp&);

namespace {
CFunctionHook*                                   g_pWindowsHook      = nullptr;
CFunctionHook*                                   g_pFullscreenHook   = nullptr;
CFunctionHook*                                   g_pShouldRenderHook = nullptr;
CFunctionHook*                                   g_pPassRenderHook   = nullptr;
std::unordered_map<WORKSPACEID, CCanvasState>    g_states;
std::unordered_map<WORKSPACEID, Time::steady_tp> g_lastTick;

bool workspaceCanvasActive(WORKSPACEID id) {
    const auto it = g_states.find(id);
    return it != g_states.end() && it->second.active();
}

void tickIfNeeded(CCanvasState& state, WORKSPACEID id, const Time::steady_tp& time) {
    auto& lastTick = g_lastTick[id];
    if (lastTick.time_since_epoch().count() != 0)
        state.tick(std::chrono::duration<double>(time - lastTick).count());
    lastTick = time;
}

// Shared by both hooks below -- windows-only rendering wrapped in our own
// translate/scale modifier, mirroring exactly how renderAllClientsForWorkspace
// itself pushes/pops SRenderModifData around a render call.
void renderWithCanvasTransform(origRenderWorkspaceWindows original, Render::IHyprRenderer* thisptr, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspace, const Time::steady_tp& time) {
    if (!pMonitor || !pWorkspace) {
        (*original)(thisptr, pMonitor, pWorkspace, time);
        return;
    }

    const auto it = g_states.find(pWorkspace->m_id);
    if (it == g_states.end() || !it->second.active()) {
        (*original)(thisptr, pMonitor, pWorkspace, time);
        return;
    }

    auto& state = it->second;
    tickIfNeeded(state, pWorkspace->m_id, time);

    const auto xf = Transform::cameraTransform(state);

    // Order matters: SRenderModifData::applyToBox applies modifs in
    // insertion order (box.scale() then box.translate(), chained). translate
    // above is pre-multiplied by scale (-pan * scale, see Transform.cpp), so
    // it must land *after* the scale step -- (pos * S) + T == (pos - pan) *
    // S. Pushing translate first would instead compute (pos + T) * S,
    // scaling the already-scaled pan term a second time (pos*S - pan*S^2),
    // which silently under-applies panning the further you zoom out.
    Render::SRenderModifData modif;
    if (xf.scale != 1.f)
        modif.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_SCALE, xf.scale);
    if (xf.translate.x != 0.0 || xf.translate.y != 0.0)
        modif.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_TRANSLATE, Vector2D{xf.translate.x, xf.translate.y});

    const bool hasModif = !modif.modifs.empty();
    if (hasModif) {
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{modif}));

        // Belt-and-suspenders alongside the CRenderPass::render hook below
        // (which fires later, at actual frame-render time): also expand
        // damage/clear clip/disable simplify directly here, immediately,
        // matching hypr-canvas's hkRenderAllClientsForWorkspace. The box is
        // the canvas-space rectangle currently visible on screen -- pan to
        // pan + monitorSize/scale -- which is exactly the coordinate range
        // a window's real (monitor-relative, never-moved-by-scale) position
        // needs to fall in to be considered "on screen" right now. Grows as
        // scale shrinks (zooming out reveals more canvas space), unlike a
        // fixed monitor-sized box, which is exactly the bug this fixes:
        // confirmed live that a plain {0,0,monitorSize} box (this file's
        // first attempt) never covered a window whose real position had
        // drifted past the monitor's own real width.
        const CBox virtualViewport{state.currentPan().x, state.currentPan().y, pMonitor->m_transformedSize.x / xf.scale, pMonitor->m_transformedSize.y / xf.scale};
        g_pHyprRenderer->m_renderData.damage.add(virtualViewport);
        g_pHyprRenderer->m_renderData.clipBox    = CBox();
        g_pHyprRenderer->m_renderData.noSimplify = true;

        // Ground-truth verification log -- reads real position + the exact
        // viewport box directly from plugin state, no screenshot needed.
        // Numeric PASS/FAIL per window per frame: grep/tail this file
        // instead of eyeballing grim output. Only written while a canvas
        // workspace is actually rendering (this branch), so it's silent the
        // rest of the time.
        static std::ofstream dbg("/tmp/canvas-verify.log", std::ios::app);
        for (auto& w : g_pCompositor->m_windows) {
            if (!w || !w->m_workspace || w->m_workspace != pWorkspace)
                continue;
            const CBox realBox{w->m_realPosition->value().x - pMonitor->m_position.x, w->m_realPosition->value().y - pMonitor->m_position.y, w->m_realSize->value().x,
                               w->m_realSize->value().y};
            const bool contained = !realBox.intersection(virtualViewport).empty();
            dbg << (contained ? "PASS " : "FAIL ") << "win=\"" << w->m_title << "\" real=(" << realBox.x << "," << realBox.y << " " << realBox.w << "x" << realBox.h << ") viewport=("
                << virtualViewport.x << "," << virtualViewport.y << " " << virtualViewport.w << "x" << virtualViewport.h << ") pan=(" << state.currentPan().x << ","
                << state.currentPan().y << ") scale=" << state.currentScale() << std::endl;
        }
    }

    (*original)(thisptr, pMonitor, pWorkspace, time);

    if (hasModif)
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{Render::SRenderModifData{}}));

    g_pHyprRenderer->damageMonitor(pMonitor);
}

void hkRenderWorkspaceWindows(Render::IHyprRenderer* thisptr, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspace, const Time::steady_tp& time) {
    renderWithCanvasTransform((origRenderWorkspaceWindows)g_pWindowsHook->m_original, thisptr, pMonitor, pWorkspace, time);
}

void hkRenderWorkspaceWindowsFullscreen(Render::IHyprRenderer* thisptr, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspace, const Time::steady_tp& time) {
    renderWithCanvasTransform((origRenderWorkspaceWindows)g_pFullscreenHook->m_original, thisptr, pMonitor, pWorkspace, time);
}

// Placing a window's canvas position by writing it straight into its *real*
// Hyprland position (WindowPlacement.cpp) runs into a second, independent
// wall on top of the render transform above: CWindow::visibleOnMonitor()
// (desktop/view/Window.cpp) checks a window's *real*, untransformed
// position against the monitor's real rectangle, and shouldRenderWindow()
// (called from renderWorkspaceWindows'/Fullscreen's own window-gathering
// loop, *before* our hook above ever runs) returns false the moment that
// check fails -- so a window panned far enough in canvas space gets
// silently dropped from the render pass entirely, no matter what transform
// we'd have applied to it. Confirmed live with ground-truth logging: two
// windows placed ~2000 canvas units apart genuinely had real positions that
// far apart (screenToCanvas/Config::Actions::move working correctly) -- only
// one ever rendered, however far zoomed out.
//
// Researched rather than guessed further: hypr-canvas (github.com/
// aaronsb/hypr-canvas, this plugin's conceptual inspiration -- see
// DESIGN.md) hits the exact same wall and solves it with exactly these two
// hooks: force shouldRenderWindow() true for windows on a canvas-active
// workspace (their real position becoming irrelevant to whether they get
// considered for rendering at all -- our render-time transform is what
// actually places them, once they're allowed into the pass), and expand
// CRenderPass::render()'s damage argument to the full monitor for such
// frames (below) so nothing gets discarded downstream either.
bool hkShouldRenderWindow(Render::IHyprRenderer* thisptr, PHLWINDOW pWindow, PHLMONITOR pMonitor) {
    const bool forced = pWindow && pMonitor && pWindow->m_workspace && pWindow->m_workspace->m_monitor.lock() == pMonitor && workspaceCanvasActive(pWindow->m_workspace->m_id);

    if (pWindow && (pWindow->m_title == "verifyA" || pWindow->m_title == "verifyB")) {
        static std::ofstream dbg("/tmp/canvas-shouldrender.log", std::ios::app);
        dbg << "hkShouldRenderWindow: win=\"" << pWindow->m_title << "\" mon=" << (pMonitor ? pMonitor->m_name : "null") << " forced=" << forced << std::endl;
    }

    if (forced)
        return true;

    return ((bool (*)(Render::IHyprRenderer*, PHLWINDOW, PHLMONITOR))g_pShouldRenderHook->m_original)(thisptr, pWindow, pMonitor);
}

// CRenderPass::simplify() (called from render(), below) separately discards
// a pass element from actually being drawn if its own boundingBox() --
// which for window content is CSurfacePassElement::getTexBox(), *also* the
// real untransformed box, same story as shouldRenderWindow() above --
// doesn't intersect this frame's damage region. Expanding the damage
// argument here, before render()/simplify() ever runs, to the canvas-space
// rectangle currently visible on screen (pan to pan + monitorSize/scale --
// same formula and reasoning as renderWithCanvasTransform's direct
// m_renderData.damage expansion above, kept in sync with it) means that
// intersection can never fail to cover wherever a window's real position
// actually is, however far zoomed out. A fixed monitor-sized box here
// (this file's first attempt) doesn't grow with zoom and silently stops
// covering a window's real position once it's drifted past the monitor's
// own real width -- confirmed live, that exact box left a second window
// undiscovered by simplify() while a first, closer one rendered fine.
CRegion hkRenderPassRender(Render::CRenderPass* thisptr, const CRegion& damage) {
    const auto original = (CRegion(*)(Render::CRenderPass*, const CRegion&))g_pPassRenderHook->m_original;

    const auto pMonitor = g_pHyprRenderer->m_renderData.pMonitor;
    if (pMonitor && pMonitor->m_activeWorkspace) {
        const auto it = g_states.find(pMonitor->m_activeWorkspace->m_id);
        if (it != g_states.end() && it->second.active()) {
            const auto& state = it->second;
            const CBox  virtualViewport{state.currentPan().x, state.currentPan().y, pMonitor->m_transformedSize.x / state.currentScale(),
                                        pMonitor->m_transformedSize.y / state.currentScale()};
            return (*original)(thisptr, CRegion{virtualViewport});
        }
    }

    return (*original)(thisptr, damage);
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
    const bool a = hookOne(handle, "renderWorkspaceWindows", "IHyprRenderer", g_pWindowsHook, (void*)::hkRenderWorkspaceWindows);
    const bool b = hookOne(handle, "renderWorkspaceWindowsFullscreen", "IHyprRenderer", g_pFullscreenHook, (void*)::hkRenderWorkspaceWindowsFullscreen);
    // shouldRenderWindow is overloaded (PHLWINDOW) and (PHLWINDOW, PHLMONITOR)
    // -- "Monitor" in the demangled signature picks the two-arg one we need,
    // since a plain "IHyprRenderer" filter alone would match either
    // ambiguously.
    const bool c = hookOne(handle, "shouldRenderWindow", "Monitor", g_pShouldRenderHook, (void*)::hkShouldRenderWindow);
    const bool d = hookOne(handle, "render", "CRenderPass", g_pPassRenderHook, (void*)::hkRenderPassRender);
    return a && b && c && d;
}

void RenderHook::uninstall() {
    if (g_pWindowsHook)
        g_pWindowsHook->unhook();
    if (g_pFullscreenHook)
        g_pFullscreenHook->unhook();
    if (g_pShouldRenderHook)
        g_pShouldRenderHook->unhook();
    if (g_pPassRenderHook)
        g_pPassRenderHook->unhook();
}

CCanvasState& RenderHook::stateFor(WORKSPACEID id) {
    return g_states[id];
}

void RenderHook::forgetWorkspace(WORKSPACEID id) {
    g_states.erase(id);
    g_lastTick.erase(id);
}
