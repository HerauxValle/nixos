// &desc: "all Hyprland CFunctionHook wiring + trampolines for the canvas plugin -- see DESIGN.md for the why"
//
// This file hooks 12 internal (non-exported, non-API) Hyprland functions via
// HyprlandAPI::createFunctionHook, plus one legitimate dispatcher for the
// Meta+Shift+C toggle. Every signature below was cross-checked against the
// Hyprland v0.55.4 tag (the version installed on this machine, confirmed via
// `hyprctl version`) -- see the header/line citations in each comment.
// createFunctionHook works by patching a trampoline at a *runtime address*
// found by demangled-name lookup, so the declared function-pointer type here
// must exactly match the real function's calling convention (arg count,
// order, and types). Get it wrong and you silently corrupt registers/stack
// on every call -- this is exactly the kind of bug that "worked" on whatever
// Hyprland commit a copy-pasted reference plugin was built against and then
// crashes (or worse, doesn't crash and just misbehaves) on a different one.

#include "HyprlandHooks.hpp"

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/PointerManager.hpp>
#include <hyprland/src/managers/XWaylandManager.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <hyprland/src/helpers/memory/Memory.hpp> // UP / makeUnique
#include <hyprland/src/devices/IKeyboard.hpp> // eKeyboardModifiers / HL_MODIFIER_*

#include <linux/input-event-codes.h> // BTN_RIGHT

using PHLMONITOR   = SP<CMonitor>;
using PHLWORKSPACE = SP<CWorkspace>;
using PHLWINDOW    = SP<Desktop::View::CWindow>;
using steady_tp     = std::chrono::steady_clock::time_point;

// g_pHyprRenderer lives at global scope despite its Render::IHyprRenderer
// type, but g_pHyprOpenGL is declared inside namespace Render::GL -- pull
// just this one symbol in rather than `using namespace Render::GL` to avoid
// silently absorbing anything else that namespace might add later.
using Render::GL::g_pHyprOpenGL;

namespace {

// --- modifier chord ---
// HL_MODIFIER_SHIFT = 1<<0, HL_MODIFIER_META = 1<<6
// (src/devices/IKeyboard.hpp:14-20 in the v0.55.4 tag). Checked with "&"
// rather than "==" so an incidental Caps-Lock bit etc. doesn't defeat the
// chord -- matches how Hyprland's own KeybindManager treats modifier masks.
constexpr uint32_t MOD_CHORD = HL_MODIFIER_META | HL_MODIFIER_SHIFT;

bool chordHeld() {
    return (g_pInputManager->getModsFromAllKBs() & MOD_CHORD) == MOD_CHORD;
}

void scheduleFrame() {
    if (auto mon = Desktop::focusState()->monitor())
        g_pCompositor->scheduleFrameForMonitor(mon);
}

// All CFunctionHook* live here, not on CCanvasState -- CFunctionHook is a
// Hyprland compositor type, and CanvasState.* was written to have zero
// knowledge of Hyprland. Keeping the hook handles here (instead of on the
// shared struct, as the hypr-canvas reference plugin does) is what actually
// enforces the hooks/logic split rather than just aspiring to it.
struct SHooks {
    CFunctionHook* mouseWheel        = nullptr;
    CFunctionHook* mouseButton       = nullptr;
    CFunctionHook* mouseMoved        = nullptr;
    CFunctionHook* position          = nullptr;
    CFunctionHook* closestValid      = nullptr;
    CFunctionHook* monitorFromCursor = nullptr;
    CFunctionHook* monitorFromVector = nullptr;
    CFunctionHook* shouldRender      = nullptr;
    CFunctionHook* renderPass        = nullptr;
    CFunctionHook* renderClients     = nullptr;
    CFunctionHook* renderWindow      = nullptr;
    CFunctionHook* popupPositioning  = nullptr;
    CFunctionHook* waylandToXWayland = nullptr;
} g_hooks;

// ============================================================================
// Input hooks -- these are the only ones gated on the Meta+Shift chord.
// Everything below them exists purely to keep rendering/coordinate-lookup
// consistent with whatever camera state these three produce.
// ============================================================================

// src/managers/input/InputManager.hpp:93 (v0.55.4):
//   void onMouseWheel(IPointer::SAxisEvent, SP<IPointer> pointer = nullptr);
using onMouseWheelFn = void (*)(CInputManager*, IPointer::SAxisEvent, SP<IPointer>);

void hkOnMouseWheel(CInputManager* self, IPointer::SAxisEvent e, SP<IPointer> pointer) {
    if (g_pCanvas->m_active && chordHeld() && e.axis == WL_POINTER_AXIS_VERTICAL_SCROLL) {
        // Direction: src/managers/KeybindManager.cpp:428-431 maps
        // `e.delta < 0` to "mouse_down" (scroll down) and `e.delta > 0` to
        // "mouse_up" (scroll up). Per explicit user request this plugin maps
        // scroll down (delta<0) -> zoom IN and scroll up (delta>0) -> zoom
        // OUT -- the opposite of the first pass, which had it backwards.
        const double d = e.deltaDiscrete != 0 ? (double)e.deltaDiscrete : e.delta;
        if (d != 0) {
            double newZoom = g_pCanvas->m_zoom * (d < 0 ? CCanvasState::ZOOM_STEP : (1.0 / CCanvasState::ZOOM_STEP));

            // Anchor at the cursor's *physical* position. Reading it through
            // the position() hook below would recurse into canvas-space
            // math we're in the middle of updating, so go via the saved
            // original implementation instead.
            auto     rawPosition = (Vector2D(*)(CPointerManager*))g_hooks.position->m_original;
            Vector2D cursorPhys  = rawPosition(g_pPointerManager.get());

            g_pCanvas->applyZoom(newZoom, cursorPhys);
            scheduleFrame();
            return; // consumed: don't fall through to normal scroll behavior
        }
    }

    auto original = (onMouseWheelFn)g_hooks.mouseWheel->m_original;
    original(self, e, pointer);
}

// src/managers/input/InputManager.hpp:92 (v0.55.4):
//   void onMouseButton(IPointer::SButtonEvent, SP<IPointer>);
// NOTE: this takes a *second* SP<IPointer> argument in 0.55.4. A widely
// circulated reference plugin (hypr-canvas) declares this hook with only one
// argument -- that was written against an older Hyprland where
// onMouseButton had no device parameter. Copying that typedef verbatim would
// have compiled (the hook function pointer cast isn't checked against the
// real target) but corrupted the call: the real function reads a second
// register-passed argument that our trampoline would never have set up.
// This is exactly the "why something didn't work" class of bug the version
// mismatch produces -- silent, no compiler error, no crash log pointing at
// the cause.
using onMouseButtonFn = void (*)(CInputManager*, IPointer::SButtonEvent, SP<IPointer>);

void hkOnMouseButton(CInputManager* self, IPointer::SButtonEvent e, SP<IPointer> pointer) {
    if (e.button == BTN_RIGHT) {
        if (g_pCanvas->m_active && chordHeld() && e.state == WL_POINTER_BUTTON_STATE_PRESSED) {
            // Deliberately no "must be empty desktop" check here (unlike
            // hypr-canvas, which restricts panning to empty space so its
            // Super+LeftDrag chord doesn't fight Hyprland's own
            // Super+LeftDrag-to-move-window default bind). Meta+Shift+RMB
            // isn't a default Hyprland bind, so there's nothing to
            // conflict with, and the user explicitly asked to be able to
            // drag "anywhere on the screen".
            g_pCanvas->m_panning = true;
            return; // consumed
        }
        if (g_pCanvas->m_panning && e.state == WL_POINTER_BUTTON_STATE_RELEASED) {
            g_pCanvas->m_panning = false;
            return; // consumed
        }
    }

    auto original = (onMouseButtonFn)g_hooks.mouseButton->m_original;
    original(self, e, pointer);
}

// src/managers/input/InputManager.hpp:90 (v0.55.4):
//   void onMouseMoved(IPointer::SMotionEvent);
using onMouseMovedFn = void (*)(CInputManager*, IPointer::SMotionEvent);

void hkOnMouseMoved(CInputManager* self, IPointer::SMotionEvent e) {
    if (g_pCanvas->m_panning) {
        // e.delta is in physical pixels; dividing by zoom converts it to
        // canvas-space movement so panning speed feels consistent
        // regardless of zoom level (drag 100 physical px while zoomed 2x
        // moves the camera 50 canvas units, matching what's on screen).
        // Subtracted because dragging right should reveal canvas content
        // to the left, i.e. move the camera opposite the drag direction.
        g_pCanvas->m_offset.x -= e.delta.x / g_pCanvas->m_zoom;
        g_pCanvas->m_offset.y -= e.delta.y / g_pCanvas->m_zoom;
        scheduleFrame();
        return; // consumed: physical cursor still moves 1:1 (see position()
                // hook below), only the camera offset changes
    }

    auto original = (onMouseMovedFn)g_hooks.mouseMoved->m_original;
    original(self, e);
}

// ============================================================================
// Coordinate-remap hooks. Hyprland assumes cursor position == screen
// position == window position everywhere; a viewport transform breaks that
// assumption, so every reader of "where is the cursor" needs to see
// canvas-space coordinates instead of physical ones, except the handful of
// places (above) that need the real physical position.
// ============================================================================

// src/managers/PointerManager.hpp:65: Vector2D position();
// 16 call sites in v0.55.4 (window-under-cursor lookups, surface-local
// coordinate math, etc.) -- hooking this one function is what makes "canvas
// mode" transparent to the rest of the compositor instead of needing a
// hook per call site.
using positionFn = Vector2D (*)(CPointerManager*);

Vector2D hkPosition(CPointerManager* self) {
    auto     original = (positionFn)g_hooks.position->m_original;
    Vector2D physical = original(self);

    if (g_pCanvas->m_active && !g_pCanvas->m_panning)
        return g_pCanvas->screenToCanvas(physical);
    // While panning, keep returning physical coords: the camera offset is
    // being updated directly from raw motion deltas in hkOnMouseMoved, so
    // remapping position() too would double-apply the pan.
    return physical;
}

// src/managers/PointerManager.hpp:104: Vector2D closestValid(const Vector2D&);
// Clamps the cursor to the physical monitor layout. When active, canvas-space
// coordinates are expected to legitimately fall outside physical monitor
// bounds (that's the whole point of an infinite canvas), so clamping must be
// disabled or the cursor could never reach zoomed-out window positions.
using closestValidFn = Vector2D (*)(CPointerManager*, const Vector2D&);

Vector2D hkClosestValid(CPointerManager* self, const Vector2D& pos) {
    if (g_pCanvas->m_active)
        return pos;
    auto original = (closestValidFn)g_hooks.closestValid->m_original;
    return original(self, pos);
}

// src/Compositor.hpp:98: PHLMONITOR getMonitorFromCursor();
// Internally calls position(), which now returns canvas coordinates that may
// not land on any real monitor -> would return null. The physical cursor is
// always on some real monitor, so short-circuit to the focused one.
using getMonitorFromCursorFn = PHLMONITOR (*)(CCompositor*);

PHLMONITOR hkGetMonitorFromCursor(CCompositor* self) {
    if (g_pCanvas->m_active)
        return Desktop::focusState()->monitor();
    auto original = (getMonitorFromCursorFn)g_hooks.monitorFromCursor->m_original;
    return original(self);
}

// src/Compositor.hpp:99: PHLMONITOR getMonitorFromVector(const Vector2D&);
// Used by vectorToWindowUnified and friends to resolve "which monitor is
// this point on" for a given coordinate. Canvas-space coordinates passed in
// (e.g. from a window's own now-remapped position) can legitimately fall
// outside every monitor; fall back to the focused monitor instead of null so
// window lookups by position keep working while zoomed/panned.
using getMonitorFromVectorFn = PHLMONITOR (*)(CCompositor*, const Vector2D&);

PHLMONITOR hkGetMonitorFromVector(CCompositor* self, const Vector2D& pos) {
    auto original = (getMonitorFromVectorFn)g_hooks.monitorFromVector->m_original;
    if (g_pCanvas->m_active) {
        if (auto result = original(self, pos))
            return result;
        return Desktop::focusState()->monitor();
    }
    return original(self, pos);
}

// ============================================================================
// Rendering hooks. These make the camera actually visible: force every
// window to be considered "on screen" for culling purposes, expand damage
// tracking to cover the whole virtual viewport (otherwise Hyprland only
// repaints the small region it thinks changed, leaving stale pixels when
// panning/zooming reveals previously off-screen content), and hand the
// pan/zoom to Hyprland's own render-modifier (translate+scale) mechanism
// instead of hand-rolling a second transform on top of it.
// ============================================================================

// src/render/Renderer.hpp:76-77 has two overloads:
//   bool shouldRenderWindow(PHLWINDOW, PHLMONITOR);
//   bool shouldRenderWindow(PHLWINDOW);
// findFunctionsByName returns both; disambiguate by demangled signature
// (the 2-arg one is the only one whose demangled text mentions CMonitor).
using shouldRenderFn = bool (*)(Render::IHyprRenderer*, PHLWINDOW, PHLMONITOR);

bool hkShouldRenderWindow(Render::IHyprRenderer* self, PHLWINDOW pWindow, PHLMONITOR pMonitor) {
    if (g_pCanvas->m_active)
        return true; // let the transform place them; don't cull by geometry
    auto original = (shouldRenderFn)g_hooks.shouldRender->m_original;
    return original(self, pWindow, pMonitor);
}

// src/render/pass/Pass.hpp: CRegion Render::CRenderPass::render(const CRegion& damage_);
using renderPassRenderFn = CRegion (*)(Render::CRenderPass*, const CRegion&);

CRegion hkRenderPassRender(Render::CRenderPass* self, const CRegion& damage) {
    auto original = (renderPassRenderFn)g_hooks.renderPass->m_original;
    if (!g_pCanvas->m_active)
        return original(self, damage);

    auto mon = Desktop::focusState()->monitor();
    if (!mon)
        return original(self, damage);

    // damage_ is in physical screen-space pixels (0..monSize), NOT canvas
    // space -- a box built from m_offset/m_zoom drifts off the monitor
    // entirely once offset != (0,0), so only a small wrongly-placed patch
    // actually gets repainted and the rest of the screen shows stale pixels
    // from the last frame. Any pan/zoom can touch every pixel, so just mark
    // the whole physical monitor damaged.
    const auto monSize = mon->m_transformedSize;
    CRegion    expanded;
    expanded.add(CBox{0, 0, monSize.x, monSize.y});
    return original(self, expanded);
}

// src/render/Renderer.hpp:253:
//   void renderAllClientsForWorkspace(PHLMONITOR, PHLWORKSPACE,
//                                      const Time::steady_tp&,
//                                      const Vector2D& translate = {0,0},
//                                      const float& scale = 1.f);
// (Time::steady_tp is `using steady_tp = std::chrono::steady_clock::time_point;`
// -- src/helpers/time/Time.hpp:10 -- so the raw std::chrono type used in this
// typedef is layout-identical.)
//
// This hook no longer folds the canvas zoom/pan into translate/scale here --
// it passes them through exactly as received. Reading Hyprland's actual
// implementation (Renderer.cpp) shows this call renders the background AND
// every layer-shell surface (bar included) internally, under whatever
// render-modifier is active for the *entire* call -- so feeding our camera
// transform in here would zoom/pan the wallpaper and bar right along with
// the windows. The camera transform is applied per-window instead, scoped
// tightly around renderWindow() (see hkRenderWindow below), which is the
// one call every window (tiled, floating, popup, pinned, fullscreen) funnels
// through. Passing translate/scale through unchanged (rather than hardcoding
// identity) also matters for a case unrelated to canvas mode: Renderer.cpp's
// renderWorkspace() calls this same function with a real, non-identity
// translate/scale for its own purposes (workspace-preview-style geometry) --
// clobbering that to identity would break whatever internal feature relies
// on it whenever canvas mode happens to be active.
using renderAllClientsFn = void (*)(Render::IHyprRenderer*, PHLMONITOR, PHLWORKSPACE, const steady_tp&, const Vector2D&, const float&);

void hkRenderAllClientsForWorkspace(Render::IHyprRenderer* self, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspace, const steady_tp& now, const Vector2D& translate,
                                     const float& scale) {
    auto original = (renderAllClientsFn)g_hooks.renderClients->m_original;

    if (!g_pCanvas->m_active) {
        original(self, pMonitor, pWorkspace, now, translate, scale);
        return;
    }

    g_pHyprRenderer->damageMonitor(pMonitor);

    const auto monSize = pMonitor->m_transformedSize;

    // Paint over the whole physical viewport first so revealing previously
    // off-screen desktop (by zooming out or panning) doesn't show whatever
    // stale pixels were left from the last frame outside the wallpaper's own
    // coverage. There's no CHyprOpenGLImpl::clear() in this Hyprland version
    // (checked -- it doesn't exist; an older one this plugin's approach was
    // modeled on apparently had one) -- renderRect with a full-monitor box
    // and default SRectRenderData{} is the equivalent available here.
    g_pHyprOpenGL->renderRect(CBox{0, 0, monSize.x, monSize.y}, CHyprColor(0.1, 0.1, 0.1, 1.0), {});

    // The live damage/clip/noSimplify state moved from CHyprOpenGLImpl to
    // IHyprRenderer::m_renderData (type Render::SRenderData,
    // src/render/types.hpp:72) at some point after whatever Hyprland version
    // the reference plugin's g_pHyprOpenGL->m_renderData accesses targeted --
    // g_pHyprOpenGL has no m_renderData member at all in v0.55.4.
    //
    // This box is in physical screen-space pixels (0..monSize), NOT canvas
    // space: a box built from m_offset/m_zoom drifts off the monitor as soon
    // as offset != (0,0), leaving only a wrongly-placed patch actually
    // repainted. Any pan/zoom can touch every pixel, so mark the whole
    // physical monitor damaged.
    g_pHyprRenderer->m_renderData.damage.add(CBox{0, 0, monSize.x, monSize.y});
    g_pHyprRenderer->m_renderData.clipBox    = {}; // no clip: nothing should be culled to the physical monitor box
    g_pHyprRenderer->m_renderData.noSimplify = true; // skip damage-region simplification that assumes small, monitor-sized regions

    original(self, pMonitor, pWorkspace, now, translate, scale); // pass through unchanged: see comment above
}

// src/render/Renderer.hpp:254:
//   void renderWindow(PHLWINDOW, PHLMONITOR, const Time::steady_tp&, bool,
//                      eRenderPassMode, bool ignorePosition = false, bool standalone = false);
// The single leaf call every window render goes through (tiled, floating,
// popup, pinned, fullscreen -- confirmed from renderWorkspaceWindows(Fullscreen)
// in Renderer.cpp, which call nothing else to put a window on screen).
// Hooking here instead of renderAllClientsForWorkspace is what keeps the
// camera transform scoped to windows only: push our own render-modifier
// hint immediately before the real call and pop it (reset to identity)
// immediately after, mirroring exactly the push/CScopeGuard-pop pattern
// Hyprland's own renderAllClientsForWorkspace uses internally, just scoped
// to one window's render instead of the whole workspace pass.
//
// NOTE: "renderWindow" is ambiguous -- src/managers/screenshare/
// ScreenshareManager.hpp:188 also declares a zero-arg `void renderWindow()`.
// findFunctionsByName returns both and hookOne() would take fns[0]
// unchecked (the same coin-flip bug DESIGN.md flags for the other ambiguous
// names), so this one goes through hookByOwner() and matches on
// "IHyprRenderer" instead.
using renderWindowFn = void (*)(Render::IHyprRenderer*, PHLWINDOW, PHLMONITOR, const steady_tp&, bool, Render::eRenderPassMode, bool, bool);

void hkRenderWindow(Render::IHyprRenderer* self, PHLWINDOW pWindow, PHLMONITOR pMonitor, const steady_tp& now, bool decorate, Render::eRenderPassMode mode,
                    bool ignorePosition, bool standalone) {
    auto original = (renderWindowFn)g_hooks.renderWindow->m_original;

    if (!g_pCanvas->m_active) {
        original(self, pWindow, pMonitor, now, decorate, mode, ignorePosition, standalone);
        return;
    }

    // (pos + translate) * scale == (pos - offset) * zoom  =>  translate = -offset
    Render::SRenderModifData modif;
    modif.modifs.emplace_back(std::make_pair<>(Render::SRenderModifData::eRenderModifType::RMOD_TYPE_TRANSLATE,
                                                Vector2D{-g_pCanvas->m_offset.x, -g_pCanvas->m_offset.y}));
    modif.modifs.emplace_back(std::make_pair<>(Render::SRenderModifData::eRenderModifType::RMOD_TYPE_SCALE, (float)g_pCanvas->m_zoom));

    g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{modif}));
    original(self, pWindow, pMonitor, now, decorate, mode, ignorePosition, standalone);
    g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{Render::SRenderModifData{}}));
}

// ============================================================================
// Protocol/UI edge cases. Both of these are "some other subsystem clamps
// coordinates to the physical monitor" bugs in disguise -- same root cause
// as closestValid()/getMonitorFromVector() above, different subsystems.
// ============================================================================

// src/protocols/XDGShell.hpp:56 (class CXDGPopupResource):
//   void applyPositioning(const CBox& availableBox, const Vector2D& t1coord);
// xdg_positioner constrains popups (right-click menus, tooltips) to the box
// it's given, which defaults to the physical monitor. When zoomed out, a
// window (and therefore its popups) can sit well outside that box, so the
// popup would get clamped back onto the monitor instead of anchoring to its
// parent. Widen the box instead of trying to compute the "real" constraint.
using applyPositioningFn = void (*)(CXDGPopupResource*, const CBox&, const Vector2D&);

void hkApplyPositioning(CXDGPopupResource* self, const CBox& availableBox, const Vector2D& t1coord) {
    auto original = (applyPositioningFn)g_hooks.popupPositioning->m_original;
    if (!g_pCanvas->m_active) {
        original(self, availableBox, t1coord);
        return;
    }
    static const CBox expanded = {-100000, -100000, 200000, 200000};
    original(self, expanded, t1coord);
}

// src/managers/XWaylandManager.hpp:24-25 has two overloads:
//   Vector2D waylandToXWaylandCoords(const Vector2D&);
//   Vector2D waylandToXWaylandCoords(const Vector2D&, PHLMONITOR);
// The reference plugin this was built from hooks whichever overload
// findFunctionsByName happens to return first, unchecked -- with two
// same-arity-ambiguous-by-name overloads that's a coin flip on this
// Hyprland build. Disambiguate the same way as shouldRenderWindow: match on
// whether the demangled signature mentions CMonitor, and only hook the
// 1-arg overload (the one XWayland apps' absolute-coordinate mapping
// actually goes through for plain cursor/window position translation).
// XWayland (X11) apps use absolute display coordinates independent of any
// Wayland-side viewport transform, so canvas-space coordinates reaching them
// unconverted would misplace/mis-click on every XWayland app (Chrome,
// Discord, etc.) whenever the canvas is active.
using waylandToXWCoordFn = Vector2D (*)(CHyprXWaylandManager*, const Vector2D&);

Vector2D hkWaylandToXWaylandCoords(CHyprXWaylandManager* self, const Vector2D& coord) {
    auto original = (waylandToXWCoordFn)g_hooks.waylandToXWayland->m_original;
    if (g_pCanvas->m_active)
        return original(self, g_pCanvas->canvasToScreen(coord));
    return original(self, coord);
}

// ============================================================================
// Toggle entry points
// ============================================================================

void toggleCanvas() {
    g_pCanvas->toggle();
    HyprlandAPI::addNotification(PHANDLE, g_pCanvas->m_active ? "[canvas] on" : "[canvas] off", CHyprColor(0.6, 0.8, 1.0, 1.0), 1500);
    scheduleFrame();
}

// Lua callback for hl.plugin.canvas.toggle(). This machine's Hyprland config
// is Lua-based (Config/Binds/canvas.lua calls
// `hl.plugin.canvas.toggle()`, matching the same `hl.plugin.<namespace>.
// <name>(...)` convention its other plugin binds already use for hyprexpo/
// scrolloverview), and that table entry only exists if the plugin itself
// registers it -- src/plugins/PluginAPI.hpp:350-356: "Register a
// plugin-owned Lua C callback under hl.plugin.<namespace>.<name>." via
// HyprlandAPI::addLuaFunction. The generic `canvas:toggle` dispatcher below
// (usable via `hyprctl dispatch canvas:toggle` or a plain hyprland.conf
// `bind = ..., canvas:toggle` line) is a separate registration and doesn't
// populate hl.plugin on its own -- confirmed from this same header that
// addDispatcherV2 and addLuaFunction are two independent registration APIs,
// not two views of the same thing.
int luaToggle(lua_State*) {
    toggleCanvas();
    return 0; // no Lua return values
}

// ============================================================================
// Hook installation
// ============================================================================

CFunctionHook* hookOne(const std::string& name, void* dest) {
    auto fns = HyprlandAPI::findFunctionsByName(PHANDLE, name);
    if (fns.empty())
        return nullptr;
    auto* hook = HyprlandAPI::createFunctionHook(PHANDLE, fns[0].address, dest);
    return (hook && hook->hook()) ? hook : nullptr;
}

// For the two ambiguous-overload targets (shouldRenderWindow,
// waylandToXWaylandCoords): pick the match whose demangled signature does/
// doesn't mention `wantMonitorArg`'s marker text, per the reasoning in the
// hook comments above.
CFunctionHook* hookOverload(const std::string& name, void* dest, bool wantsMonitorArg) {
    for (auto& fn : HyprlandAPI::findFunctionsByName(PHANDLE, name)) {
        const bool hasMonitorArg = fn.demangled.find("CMonitor") != std::string::npos;
        if (hasMonitorArg == wantsMonitorArg) {
            auto* hook = HyprlandAPI::createFunctionHook(PHANDLE, fn.address, dest);
            return (hook && hook->hook()) ? hook : nullptr;
        }
    }
    return nullptr;
}

// "render" alone is a near-useless search string in a compositor codebase --
// Render::IHyprRenderer::render, IHyprWindowDecoration::render, and others all match
// it. Require the demangled text to name CRenderPass specifically so this
// doesn't silently hook the wrong function (the same class of bug as the
// unguarded overload picks above, just for a name collision instead of an
// argument-count collision).
CFunctionHook* hookByOwner(const std::string& name, const std::string& ownerMarker, void* dest) {
    for (auto& fn : HyprlandAPI::findFunctionsByName(PHANDLE, name)) {
        if (fn.demangled.find(ownerMarker) != std::string::npos) {
            auto* hook = HyprlandAPI::createFunctionHook(PHANDLE, fn.address, dest);
            return (hook && hook->hook()) ? hook : nullptr;
        }
    }
    return nullptr;
}

} // namespace

bool CanvasHooks::init(HANDLE handle) {
    PHANDLE  = handle;
    g_pCanvas = std::make_unique<CCanvasState>();

    g_hooks.mouseWheel        = hookOne("onMouseWheel", (void*)&hkOnMouseWheel);
    g_hooks.mouseButton       = hookOne("onMouseButton", (void*)&hkOnMouseButton);
    g_hooks.mouseMoved        = hookOne("onMouseMoved", (void*)&hkOnMouseMoved);
    g_hooks.position          = hookOne("position", (void*)&hkPosition);
    g_hooks.closestValid      = hookOne("closestValid", (void*)&hkClosestValid);
    g_hooks.monitorFromCursor = hookOne("getMonitorFromCursor", (void*)&hkGetMonitorFromCursor);
    g_hooks.monitorFromVector = hookOne("getMonitorFromVector", (void*)&hkGetMonitorFromVector);
    g_hooks.popupPositioning  = hookOne("applyPositioning", (void*)&hkApplyPositioning);
    g_hooks.shouldRender      = hookOverload("shouldRenderWindow", (void*)&hkShouldRenderWindow, /*wantsMonitorArg=*/true);
    g_hooks.renderPass        = hookByOwner("render", "CRenderPass", (void*)&hkRenderPassRender);
    g_hooks.renderClients     = hookOne("renderAllClientsForWorkspace", (void*)&hkRenderAllClientsForWorkspace);
    g_hooks.renderWindow      = hookByOwner("renderWindow", "IHyprRenderer", (void*)&hkRenderWindow);
    g_hooks.waylandToXWayland = hookOverload("waylandToXWaylandCoords", (void*)&hkWaylandToXWaylandCoords, /*wantsMonitorArg=*/false);

    const bool allHooked = g_hooks.mouseWheel && g_hooks.mouseButton && g_hooks.mouseMoved && g_hooks.position && g_hooks.closestValid &&
        g_hooks.monitorFromCursor && g_hooks.monitorFromVector && g_hooks.popupPositioning && g_hooks.shouldRender && g_hooks.renderPass &&
        g_hooks.renderClients && g_hooks.renderWindow && g_hooks.waylandToXWayland;

    if (!allHooked) {
        // Deliberately refuse to run half-hooked: e.g. position() remapping
        // cursor coords without the matching closestValid()/monitor-lookup
        // hooks would let the cursor get clamped back onto the physical
        // monitor mid-frame, desyncing "where Hyprland thinks the cursor is"
        // from "what screenToCanvas() computed" in a way that's very hard to
        // debug after the fact. Fail loudly at load time instead.
        HyprlandAPI::addNotification(PHANDLE, "[canvas] failed to install all hooks -- unloading. Check your Hyprland version against DESIGN.md.",
                                      CHyprColor(1.0, 0.2, 0.2, 1.0), 8000);
        shutdown();
        return false;
    }

    HyprlandAPI::addDispatcherV2(PHANDLE, "canvas:toggle", [](std::string) -> SDispatchResult {
        toggleCanvas();
        return SDispatchResult{};
    });
    HyprlandAPI::addLuaFunction(PHANDLE, "canvas", "toggle", &luaToggle);

    return true;
}

void CanvasHooks::shutdown() {
    for (auto* h : {g_hooks.mouseWheel, g_hooks.mouseButton, g_hooks.mouseMoved, g_hooks.position, g_hooks.closestValid, g_hooks.monitorFromCursor,
                     g_hooks.monitorFromVector, g_hooks.popupPositioning, g_hooks.shouldRender, g_hooks.renderPass, g_hooks.renderClients,
                     g_hooks.renderWindow, g_hooks.waylandToXWayland}) {
        if (h)
            HyprlandAPI::removeFunctionHook(PHANDLE, h);
    }
    g_hooks = {};
    HyprlandAPI::removeLuaFunction(PHANDLE, "canvas", "toggle");
    g_pCanvas.reset();
}
