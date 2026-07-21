/* &desc: "RenderHook implementation -- hooks IHyprRenderer::renderWorkspaceWindows(Fullscreen), windows only." */
#include "RenderHook.hpp"

#include "../canvas/Transform.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/types.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <hyprland/src/helpers/Monitor.hpp>
#include <hyprland/src/desktop/Workspace.hpp>

#include <chrono>
#include <unordered_map>

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
CFunctionHook*                                   g_pWindowsHook     = nullptr;
CFunctionHook*                                   g_pFullscreenHook  = nullptr;
std::unordered_map<WORKSPACEID, CCanvasState>    g_states;
std::unordered_map<WORKSPACEID, Time::steady_tp> g_lastTick;

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
    // scaling the already-scaled pan term a second time (pos*S - pan*S²),
    // which silently under-applies panning the further you zoom out. Caught
    // by hand-deriving the math against zoomImpl's documented formula
    // (screenPos = (canvasPos - pan) * scale) rather than live symptoms.
    Render::SRenderModifData modif;
    if (xf.scale != 1.f)
        modif.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_SCALE, xf.scale);
    if (xf.translate.x != 0.0 || xf.translate.y != 0.0)
        modif.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_TRANSLATE, Vector2D{xf.translate.x, xf.translate.y});

    const bool hasModif = !modif.modifs.empty();
    if (hasModif)
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{modif}));

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

bool hookOne(HANDLE handle, const char* fnName, CFunctionHook*& slot, void* trampoline) {
    const auto FNS = HyprlandAPI::findFunctionsByName(handle, fnName);
    for (auto& fn : FNS) {
        if (!fn.demangled.contains("IHyprRenderer"))
            continue;
        slot = HyprlandAPI::createFunctionHook(handle, fn.address, trampoline);
        break;
    }
    return slot && slot->hook();
}
}

bool RenderHook::install(HANDLE handle) {
    const bool a = hookOne(handle, "renderWorkspaceWindows", g_pWindowsHook, (void*)::hkRenderWorkspaceWindows);
    const bool b = hookOne(handle, "renderWorkspaceWindowsFullscreen", g_pFullscreenHook, (void*)::hkRenderWorkspaceWindowsFullscreen);
    return a && b;
}

void RenderHook::uninstall() {
    if (g_pWindowsHook)
        g_pWindowsHook->unhook();
    if (g_pFullscreenHook)
        g_pFullscreenHook->unhook();
}

CCanvasState& RenderHook::stateFor(WORKSPACEID id) {
    return g_states[id];
}

void RenderHook::forgetWorkspace(WORKSPACEID id) {
    g_states.erase(id);
    g_lastTick.erase(id);
}
