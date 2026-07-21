/* &desc: "RenderHook implementation -- hooks IHyprRenderer::renderWindow (per-window), pairs each window's stored canvas-space position against its real Hyprland position." */
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
#include <fstream>
#include <unordered_map>

// Originally hooked renderWorkspaceWindows/renderWorkspaceWindowsFullscreen
// (one shared transform for an entire render call's worth of windows) --
// abandoned after live testing: that approach encodes each window's
// canvas-space position by writing it into the window's *real* Hyprland
// position (Config::Actions::move), which is the only way two windows can
// end up visually separated by a single whole-call transform. That runs
// straight into CWindow::visibleOnMonitor (desktop/view/Window.cpp), a
// native Hyprland visibility gate -- checked from shouldRenderWindow
// *before* any render hook gets a chance to run -- that compares a window's
// *real*, untransformed position against the monitor's real rectangle. Pan
// far enough and a window's real position lands outside the monitor's real
// bounds; Hyprland drops it from that monitor's render pass entirely,
// regardless of what our transform would have done. Confirmed live: two
// windows placed ~2000 canvas units apart (confirmed via hyprctl clients
// that their real positions really did differ by that amount) -- only one
// ever rendered, however far zoomed out. If a window's real position
// happened to land on a *neighboring* monitor's real rectangle instead,
// Hyprland's own cross-monitor floating-window rendering drew it there,
// full size, completely untransformed.
//
// The fix: never write canvas position into real position at all. Each
// window's canvas-space position lives in g_canvasPos here, entirely
// decoupled from wherever Hyprland's own default floating placement put its
// *real* box (which stays wherever Hyprland put it -- always safely
// on-monitor, so visibleOnMonitor never has a reason to exclude it). This
// hook computes a *per-window* transform -- translate/scale from the
// difference between where a window actually is (real) and where it should
// visually appear (canvas position, camera pan/scale) -- instead of one
// transform shared across everything a render call draws.
using origRenderWindow = void (*)(Render::IHyprRenderer*, PHLWINDOW, PHLMONITOR, const Time::steady_tp&, bool, Render::eRenderPassMode, bool, bool);

namespace {
CFunctionHook*                                   g_pHook = nullptr;
std::unordered_map<WORKSPACEID, CCanvasState>    g_states;
std::unordered_map<WORKSPACEID, Time::steady_tp> g_lastTick;
std::unordered_map<Desktop::View::CWindow*, CanvasVec2> g_canvasPos;

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

void hkRenderWindow(Render::IHyprRenderer* thisptr, PHLWINDOW pWindow, PHLMONITOR pMonitor, const Time::steady_tp& time, bool decorate, Render::eRenderPassMode mode, bool ignorePosition,
                     bool standalone) {
    const auto original = (origRenderWindow)g_pHook->m_original;

    {
        static std::ofstream dbg2("/tmp/canvas-debug2.log", std::ios::app);
        dbg2 << "hook called: win=" << (pWindow ? (void*)pWindow.get() : nullptr) << " mon=" << (pMonitor ? pMonitor->m_name : "null")
             << " ws=" << (pWindow && pWindow->m_workspace ? std::to_string(pWindow->m_workspace->m_id) : "none") << std::endl;
    }

    if (!pWindow || !pMonitor || !pWindow->m_workspace) {
        (*original)(thisptr, pWindow, pMonitor, time, decorate, mode, ignorePosition, standalone);
        return;
    }

    const auto it = g_states.find(pWindow->m_workspace->m_id);
    // Only transform when this window is rendering on its *own* workspace's
    // owning monitor -- leaves the rare "floating window visible on a
    // neighboring monitor" case (a different, non-canvas render context)
    // untouched, rather than double-transforming or transforming with the
    // wrong workspace's camera.
    if (it == g_states.end() || !it->second.active() || pWindow->m_workspace->m_monitor.lock() != pMonitor) {
        static std::ofstream dbg3("/tmp/canvas-debug2.log", std::ios::app);
        dbg3 << "  -> early return: inStates=" << (it != g_states.end()) << " active=" << (it != g_states.end() && it->second.active())
             << " monMatch=" << (pWindow->m_workspace->m_monitor.lock() == pMonitor) << std::endl;
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

    {
        static std::ofstream dbg("/tmp/canvas-debug.log", std::ios::app);
        dbg << "win=" << pWindow.get() << " canvasPos=(" << mapIt->second.x << "," << mapIt->second.y << ") realPos=(" << realMonRelative.x << "," << realMonRelative.y << ") pan=("
            << state.currentPan().x << "," << state.currentPan().y << ") scale=" << state.currentScale() << " translate=(" << xf.translate.x << "," << xf.translate.y
            << ") xfScale=" << xf.scale << std::endl;
    }

    // Order matters: applyToBox applies modifs in insertion order
    // (box.scale() then box.translate(), chained) -- windowTransform's
    // translate is derived assuming scale lands first (see its own
    // comment), so push scale before translate here to match.
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
}

bool RenderHook::install(HANDLE handle) {
    const auto FNS = HyprlandAPI::findFunctionsByName(handle, "renderWindow");
    for (auto& fn : FNS) {
        if (!fn.demangled.contains("IHyprRenderer"))
            continue;
        g_pHook = HyprlandAPI::createFunctionHook(handle, fn.address, (void*)::hkRenderWindow);
        break;
    }
    return g_pHook && g_pHook->hook();
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
