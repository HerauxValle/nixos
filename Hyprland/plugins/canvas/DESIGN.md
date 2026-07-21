# canvas — an infinite canvas per Hyprland workspace

## Purpose & provenance

Original implementation. Inspired in *concept only* by the third-party plugin
[hypr-canvas](https://github.com/aaronsb/hypr-canvas) — its README/feature
description was used as a functional spec, its code was never read or copied.
We tried wiring hypr-canvas up first; its pinned commit hooks
`renderAllClientsForWorkspace` with a signature that no longer matches
Hyprland 0.55.4's actual internal function (it hooks `CHyprRenderer*`, but
that class was renamed to `Render::IHyprRenderer` at some point upstream).
hypr-canvas has no version tags/branches to fall back to — this is the
inherent fragility of plugins that hook deep into Hyprland internals across
compositor versions.

The actual shape of this plugin changed significantly during a live
implementation/debugging session, based on direct user feedback:

1. First attempt: hook `renderAllClientsForWorkspace` to fan one call into
   many (one per grid slot), rendering *every* workspace on a monitor
   simultaneously in a grid, like a wall of thumbnails.
2. That broke visibly live (a workspace toggled into "grid mode" showed a
   blank/gray monitor) and, once fixed for the immediate cause, still failed
   for a structural reason: `IHyprRenderer::shouldRenderWindow` (real source,
   not just the header) gates window rendering on `CWorkspace::isVisible()`
   — a genuine "is this the workspace actually switched-to" compositor flag,
   not whichever workspace happens to be passed into the render call. Windows
   on any workspace other than the monitor's real active one structurally
   don't render this way, no matter the translate/scale used.
3. The user reframed the actual goal, inspired by ComfyUI: not "see every
   numbered workspace glued into one grid," but "each workspace is its own
   infinite 2D space you can pan/zoom around, with windows placed anywhere in
   it like nodes on a canvas." That sidesteps the whole problem above —
   there's only ever one workspace being rendered (the real active one), just
   with its own floating windows free to sit at coordinates far outside the
   monitor's normal pixel bounds, revealed by panning/zooming a per-workspace
   camera.

## Architecture

```
Hyprland/plugins/canvas/
├── Makefile
├── DESIGN.md
├── flake.nix                 -- dev convenience only, see below
└── src/
    ├── main.cpp               -- pluginAPIVersion/pluginInit/pluginExit, wiring only
    ├── hypr/                  -- Layer A: anything touching Hyprland internals/types
    │   ├── VersionGuard.{hpp,cpp}
    │   ├── RenderHook.{hpp,cpp}
    │   ├── Dispatchers.{hpp,cpp}
    │   └── WindowPlacement.{hpp,cpp}
    └── canvas/                -- Layer B: pure logic, zero Hyprland #includes
        ├── CanvasState.{hpp,cpp}
        └── Transform.{hpp,cpp}
```

`canvas/` defines its own tiny `struct CanvasVec2 { double x, y; }` instead of
reusing Hyprland's `Vector2D`, so this layer has zero `#include` on anything
from `pkgs.hyprland` — sanity-checkable with a bare `g++ -c canvas/*.cpp`, no
Hyprland include path at all (verified during implementation). If Hyprland's
internals change again, only files under `src/hypr/` should ever need
editing.

### Layer B (`canvas/`) — pure logic

- `CCanvasState`: one instance *per workspace* (see `RenderHook::stateFor`).
  `activate()/deactivate()/toggle()`, `zoomBy(step)/zoomTo(scale)`,
  `panBy(delta)/panTo(pos)`, `reset()`, `tick(dt)` (eases current toward
  target — clamps zoom to `[0.15, 1.0]`, never zooms in past 1:1).
- `Transform::cameraTransform(state) -> {translate, scale}` — what to feed
  `renderAllClientsForWorkspace` so this workspace's windows appear
  panned/zoomed correctly.
- `Transform::screenToCanvas(state, screenPos) -> canvasPos` — the inverse,
  used to place new windows at the cursor instead of a fixed origin.

### Layer A (`hypr/`) — the fragile glue

- **`RenderHook`**: hooks two functions,
  `IHyprRenderer::renderWorkspaceWindows` and
  `IHyprRenderer::renderWorkspaceWindowsFullscreen`. Originally hooked the
  single, wider `renderAllClientsForWorkspace` instead, wrapping its
  translate/scale modifier around the *entire* call — but that function also
  draws that workspace's background and layer-shell surfaces (wallpaper, and
  crucially TOP/OVERLAY-layer bars/panels), confirmed live as a quickshell
  bar zooming along with the windows. Traced the real `Renderer.cpp`:
  `renderAllClientsForWorkspace` calls exactly one of these two narrower
  functions to draw *just* the windows (tiled/floating/pinned, no layers),
  sandwiched between its own background/bottom-layer rendering (before) and
  top/overlay-layer rendering (after) — both left untouched now. Each hook's
  `translate`/`scale` work by pushing a render-pass-wide modifier
  (`SRenderModifData`/`CRendererHintsPassElement`) that's popped again before
  the function returns — so this hook only ever needs to override the
  transform for the *one* workspace Hyprland already asked to render; it
  never touches any other workspace's render at all. When the workspace
  isn't in canvas mode, it passes through whatever translate/scale Hyprland
  itself supplied, untouched (something else, e.g. the built-in cursor-zoom
  accessibility feature, could legitimately already be using this same
  parameter). Order matters when both modifs are pushed: `applyToBox` applies
  them in insertion order, and `Transform::cameraTransform`'s translate is
  pre-multiplied by scale (`-pan * scale`), so scale must be pushed *before*
  translate — pushing translate first double-scales the pan term
  (`pos*S - pan*S²` instead of `pos*S - pan*S`), silently under-applying pan
  the further you zoom out. (Caught and fixed by hand-deriving the math, not
  a live symptom report.)
  Owns the `std::unordered_map<WORKSPACEID, CCanvasState>` — each workspace's
  camera is independent, matching "one workspace = one infinite canvas."
- **`VersionGuard`**: compares `__hyprland_api_get_hash()` (running server)
  against `__hyprland_api_get_client_hash()` (this plugin's own compile-time
  hash) — the same idiom the official `csgo-vulkan-fix` plugin uses. On
  mismatch: a visible notification, and `RenderHook::install` is skipped
  (dispatchers still register, so `canvas:*` commands don't hard-crash) — a
  "degraded, hooks off" state rather than silent misbehavior. Deliberately
  softer than upstream's own convention (`throw` and abort `pluginInit`).
- **`Dispatchers`**: registers `toggle`/`zoom`/`pan`/`panDrag`/`reset` via
  *both* `addDispatcherV2` (legacy `bind = ...` text config) *and*
  `addLuaFunction` (`hl.plugin.canvas.<name>(...)` from Lua config) — this
  system's actual config is Lua-based, and empirically its keybind framework
  calls plugin actions via `hl.plugin.<name>.<x>(...)`, not the legacy
  dispatcher-table route. Each dispatcher acts on
  `RenderHook::stateFor(currentWorkspaceID())`, where "current" is the active
  workspace of whichever monitor the cursor is over. `toggle()`, when turning
  a workspace *on*, also floats every existing window on it via
  `Config::Actions::floatWindow`, and disables decoration (border/shadow) on
  every existing window via `Config::Actions::setProp("decorate", ...)` (see
  "Window decorations don't respect the canvas transform" below) — reversed
  (`"unset"`, not hardcoded back to enabled, in case a rule already disabled
  it) when turning a workspace back *off*.
- **`WindowPlacement`**: subscribes to the stable `EventBus`
  (`m_events.window.open`, `m_events.workspace.removed`,
  `m_events.window.moveToWorkspace`) — no extra function hook needed for
  this, the event bus is Hyprland's own sanctioned pub/sub layer used
  throughout its codebase, not just by plugins. On `window.open`, if the
  window's workspace is in canvas mode, it schedules a short (50ms) deferred
  callback via `CEventLoopTimer` to float the window, disable its
  decoration, and move it to the cursor's canvas position. On
  `window.moveToWorkspace`, it re-syncs *just* the decoration override
  (never position/floating — that would mean teleporting a window to the
  cursor just because it got moved, not because it's genuinely new) to
  match the destination workspace's canvas state, since a window carries a
  decoration override with it across a plain move-to-workspace action and
  neither `toggle`'s sweep nor `onWindowOpen` re-run for a window that's
  already left the workspace they were scoped to.

### `Config::Actions` — direct C++ calls, not hyprctl strings

Originally this floated/moved windows via
`HyprlandAPI::invokeHyprctlCommand("dispatch", "setfloating address:... 1")`
(string-based, matching a normal `hyprctl dispatch` call). That failed
outright on this system: its Lua config wraps hyprctl's `dispatch` command
itself, expecting a Lua expression (`hl.dispatch(hl.dsp.window.close())`)
rather than legacy `dispatcher arg` text — and `invokeHyprctlCommand` goes
through the exact same wrapper, so it failed identically, silently (the
return string carried the Lua parse error, which nothing was checking).

The fix, found by tracing Hyprland's own Lua dispatcher bindings
(`src/config/lua/bindings/LuaBindingsDispatchers.cpp`) back to their real
implementation: every dispatcher — legacy string-based, Lua-based, or ours —
ultimately calls into a single, stable, directly-callable C++ layer:
`Config::Actions::*` (`src/config/shared/actions/ConfigActions.hpp`, ships in
the dev headers). Calling `Config::Actions::floatWindow(...)` and
`Config::Actions::move(...)` directly skips *both* the legacy-dispatcher and
Lua-config layers entirely — no string formatting, no config-mode
dependency, works identically regardless of what config system (Lua or
legacy) the user has. This is arguably more robust than routing through
`hyprctl` at all, and is now this plugin's preferred mechanism for anything
`Config::Actions` covers.

### Window decorations don't respect the canvas transform — decoration is turned off instead

First live-tested end to end (screenshots, not just `hyprctl` state) after the
rest of this plugin already looked done: zoomed/panned a workspace and got a
window rendered as a small, correctly-scaled, correctly-positioned rectangle
of *content* sitting inside a much larger, unscaled, unmoved rectangular
outline — the window's real-size border/shadow, at its real (untransformed)
screen position, with the actual shrunk content nested near its top-left
corner. Traced against the real render source
(`render/decorations/CHyprBorderDecoration.cpp`,
`render/decorations/CHyprDropShadowDecoration.cpp`,
`render/gl/GLElementRenderer.cpp`): border/shadow/inner-glow decorations are
computed from the window's *real* geometry and the monitor's DPI
`m_scale` only — none of them ever call `SRenderModifData::applyToBox` or
read `m_renderData.renderModif`. Only surface content
(`CSurfacePassElement`, queued via `m_renderPass.add` and consulted at actual
draw time) respects the render-modifier pipeline our `RenderHook` pushes.
This is a genuine, structural gap in Hyprland's decoration rendering, not a
timing bug on our end: decorations simply don't participate in this
mechanism at all, for anyone's use of it (plugin or Hyprland's own).

Making decorations respect our transform properly would need hooking
multiple additional, deeper internals — `CHyprBorderDecoration::draw` bakes
its box eagerly at queue time (would need intercepting before/as it's
computed), while shadow/inner-glow are computed *lazily*, from a stored
decoration pointer, at actual GL-draw time (a different code path again) —
each one more fragile, private-internal surface added to the ledger below
for a purely cosmetic payoff.

Instead: decoration is simply switched off for the duration of canvas mode,
via `Config::Actions::setProp("decorate", "0"/"unset", window)` — the same
direct-call mechanism `hyprctl setprop <addr> decorate 0` resolves to, and
the same `Config::Actions` pattern already used for `floatWindow`/`move`
above (see `Dispatchers::setDecorateOnCurrentWorkspace`). No borders/shadows
to desync from content in the first place, and it fits the ComfyUI-node
aesthetic this plugin is going for anyway (bare content, no native window
chrome). Applied both at toggle-on (sweep over existing windows) and at
new-window placement (`WindowPlacement.cpp`, since a window opened *while*
canvas mode is already active never goes through the toggle-time sweep);
reversed with `"unset"` (not hardcoded back to `"1"`) at toggle-off, so a
window rule that already disabled decoration isn't clobbered.

This very likely also explains the "click an edge to move, mouse ends up
resizing by a completely different amount than the window moved" complaint
from manual testing: hit-testing (focus resolution, resize-margin detection)
always uses a window's *real* geometry, which is exactly where that phantom
oversized border was rendering — a click that looked like "near the visible
edge" was, not coincidentally, also right at the window's *real* resize
margin. With decoration off there's no border to visually invite that click
in the first place. Genuinely correct hit-testing for the small *content*
rectangle itself while zoomed/panned is a separate, harder problem — see
"Non-goals" below, unchanged from before this fix.

### The deferred-placement timer — a second, small fragility point

`WindowPlacement`'s new-window placement doesn't take effect immediately at
`window.open` — confirmed live via logging that an immediate `move()` call's
*goal* was set correctly, but Hyprland's own initial floating-window
placement (centering the window on its monitor) runs shortly after and
overwrites it. A 50ms deferred `CEventLoopTimer` lets that settle first, so
this plugin's positioning is the last word. This is a real, if small,
dependency on *when* Hyprland's own centering logic runs relative to the
`open` event — see the fragility ledger below.

## Fragility ledger

| Hook / dependency | Exact signature/behavior relied on | File | Why | What breaks if it changes | First thing to check after a Hyprland bump |
|---|---|---|---|---|---|
| `renderWorkspaceWindows`/`renderWorkspaceWindowsFullscreen` hooks | `void(IHyprRenderer*, PHLMONITOR, PHLWORKSPACE, const Time::steady_tp&)`, each called from within `renderAllClientsForWorkspace` | `hypr/RenderHook.cpp` | Only hook point that lets a workspace's windows render at a different position/scale than 1:1, without also zooming background/layer-shell surfaces (bars/panels) — no stable API covers render transforms | Signature change, class rename (already happened once upstream: `CHyprRenderer` → `Render::IHyprRenderer`), or `renderAllClientsForWorkspace` no longer calling exactly one of these two per invocation | Diff `Renderer.hpp`'s declarations; re-run `findFunctionsByName` and compare `SFunctionMatch::demangled` against what was captured at last successful build; re-grep the real `Renderer.cpp` source for how `renderAllClientsForWorkspace` dispatches to these |
| `getMouseCoordsInternal()` read | `Vector2D CInputManager::getMouseCoordsInternal()` returning **global** desktop coordinates | `hypr/Dispatchers.cpp`, `hypr/WindowPlacement.cpp` | Live cursor position for drag-pan deltas and new-window placement | Read, not a hook — lower risk, but the coordinate-space assumption (global vs. monitor-relative) is a real, confirmed-the-hard-way gotcha; if this ever returns something else, math silently goes wrong rather than crashing | Sanity-check a known cursor position against `hyprctl cursorpos` |
| Deferred-placement timing | Hyprland's own floating-window centering logic runs *after* `window.open` fires; 50ms is empirically enough to settle first | `hypr/WindowPlacement.cpp` | New windows would otherwise snap back to a centered default instead of the cursor position | If the centering logic's timing changes (faster/slower), the deferred move could race it again (window ends up centered, not at cursor) | If new windows stop landing at the cursor, first suspect: increase the timer delay and see if it starts working again |
| `Config::Actions::floatWindow`/`move`/`setProp` | `ActionResult floatWindow(eTogglableAction, std::optional<PHLWINDOW>)`, `ActionResult move(const Vector2D&, bool, std::optional<PHLWINDOW>)`, `ActionResult setProp(const std::string&, const std::string&, std::optional<PHLWINDOW>)` | `hypr/Dispatchers.cpp`, `hypr/WindowPlacement.cpp` | Direct, config-mode-independent equivalents of the `setfloating`/`move`/`setprop` dispatchers — bypasses the Lua-config `dispatch` wrapper that broke `invokeHyprctlCommand` entirely on this system. `setProp("decorate", "0"/"unset", w)` is how canvas mode turns decoration off/on (see "Window decorations don't respect the canvas transform" above) | If these functions are renamed/restructured, floating/positioning/decoration-toggling stops working (each call already checks its `ActionResult` and is safe to no-op on failure); if `setProp`'s accepted `"decorate"` string or its `parsePropTrivial`/`truthy()` value parsing changes, decoration stops toggling silently | Re-check `src/config/shared/actions/ConfigActions.hpp` for the current function signatures; grep `ConfigActions.cpp`'s `setProp` for the current `"decorate"` branch |
| Window decorations bypass the render-modifier pipeline | `CHyprBorderDecoration::draw`/`CHyprDropShadowDecoration::getRenderData` compute their box from real window geometry + `pMonitor->m_scale` only, never `SRenderModifData`/`m_renderData.renderModif` | n/a (worked around, not hooked — see "Window decorations don't respect the canvas transform" above) | Confirmed by reading `render/decorations/*.cpp` and `render/gl/GLElementRenderer.cpp` directly, not inferred | If a future Hyprland version *does* route decorations through `applyToBox`, `setDecorateOnCurrentWorkspace` turning decoration off entirely becomes an unnecessary workaround (harmless, just no longer needed) rather than a broken one | Grep `CHyprBorderDecoration::draw`/shadow `getRenderData` for `renderModif`/`applyToBox`; if present now, decoration-off could be replaced with a real transform |
| Render-modifier push order (`SCALE` before `TRANSLATE`) | `SRenderModifData::applyToBox` applies `modifs` in insertion order (`box.scale()` then `box.translate()`, chained) | `hypr/RenderHook.cpp` | `Transform::cameraTransform`'s translate is pre-multiplied by scale (`-pan * scale`) — only correct if scale lands *before* translate; pushing translate first double-scales the pan term (confirmed by hand-deriving the math, then confirmed live via screenshot after fixing) | If `applyToBox`'s modifs application ever stops being pure left-to-right insertion order, or `Transform::cameraTransform`'s translate formula changes without updating this push order to match, pan silently drifts from the documented `screenPos = (canvasPos - pan) * scale` formula the further a workspace is zoomed out | Re-derive by hand against `Dispatchers.cpp`'s `zoomImpl` comment (the canonical formula) whenever either file changes |
| `window.moveToWorkspace` event | `Event<PHLWINDOW, PHLWORKSPACE> moveToWorkspace` on `Event::bus()->m_events.window` | `hypr/WindowPlacement.cpp` | Only signal that a window's workspace changed via something *other* than open/close — needed to keep a canvas-applied decoration override from following a window forever once it leaves the workspace that applied it | If renamed/removed/resignatured, decoration desync returns for exactly this one case (moved windows) — silent, cosmetic-only, not a crash | Grep `event/EventBus.hpp`'s `window` struct for the current event list/signature |
| Version guard | `__hyprland_api_get_hash()` vs `__hyprland_api_get_client_hash()` | `hypr/VersionGuard.cpp` | Official idiom (matches `csgo-vulkan-fix`) — Hyprland's own loader already gates on this hash via `dlsym` per `PluginAPI.hpp`'s comments, so this guard's value is a friendlier, visible failure mode, not a hole Hyprland otherwise leaves open | n/a — this is Hyprland's own mechanism | Confirm both functions still exist with this shape before assuming the guard compiles |

## Non-goals / explicitly deferred

- **Click-to-focus / hit-testing while zoomed out**: clicking a window at its
  shrunk/panned position should focus it. Not implemented. (The worse-than-
  expected version of this — clicking near a visible edge resizing instead
  of moving, by a wildly disproportionate amount — was actually the window-
  decoration bug above: hit-testing was landing on a real, full-size,
  invisible-in-intent-but-very-visible-in-practice border. With decoration
  off that specific confusion should be gone; genuine "click the small
  content rectangle itself" hit-testing is still this same unimplemented
  non-goal.)

  Investigated properly in the bugfix follow-up session, not just deferred
  on a hunch: the one plausible mechanism is the stable `EventBus`'s
  `Cancellable<Vector2D> input.mouse.move` / `Cancellable<SButtonEvent>
  input.mouse.button` signals (`CInputManager::onMouseMoveOverride`/
  `onMouseButton` in `managers/input/InputManager.cpp`, traced against the
  real source, not just headers). Both turn out to be **all-or-nothing
  gates over the entire mouse pipeline**, not a scoped remap point: the
  coordinate/event is emitted *before* any of Hyprland's own focus/hit-test
  logic runs, and `SCallbackInfo::cancelled` is the only lever a listener
  has — setting it skips constraint handling, DND, layer-surface focus,
  resize-on-border detection, and `processMouseDownNormal`'s click routing
  *for that event entirely*. There's no "let Hyprland's coordinate-to-window
  resolution use a different point, then continue normally" — using this
  safely would mean reimplementing that whole pipeline in the plugin.
  Genuinely out of proportion to the payoff and a real risk to global input
  if done imperfectly (stuck grabs, unresponsive windows, broken drag-resize
  everywhere else) — recommended **not** to pursue this route. If this ever
  gets revisited, the real question to answer first is whether Hyprland
  exposes *any* narrower "coordinate → window" resolution function a plugin
  could call standalone (to resolve a click against the canvas-space point
  instead of the screen point, then dispatch focus manually) rather than
  intercepting the live input event stream at all.
- **Tiled-window canvas behavior**: canvas mode is floating-only by design
  (user's explicit choice, ComfyUI-style free placement). A workspace with
  tiled windows keeps them tiled/at their normal position when canvas mode
  turns on for *existing* windows other than what `floatAllWindowsOnCurrentWorkspace`
  catches at toggle time; only genuinely new windows and previously-untiled
  ones are guaranteed floating.
- **Popup/constraint positioning, XWayland coordinate translation**: not
  investigated at all — out of scope unless a real need shows up.

## Build system: real Makefile, not an inline Nix `buildPhase`

Consumed by `mkPlugin`'s generic `stdenv.mkDerivation` (default `make`/`make
install` phases), matching every other plugin entry in
`Nixos/modules/hyprland/plugins/default.nix`. `out ?= /usr/local` in the
Makefile honors Nix's `$out` automatically inside the sandbox, and falls back
sanely for a standalone `make && make install` outside Nix. `--no-gnu-unique`
matches the flag official Hyprland plugins (e.g. `hyprland-plugins`'
`borders-plus-plus`) apply for g++, avoiding `STB_GNU_UNIQUE` symbol-binding
issues across dlopen'd plugins sharing inline globals with the host process.

## Dev flake

`flake.nix` in this directory is for standalone `nix build`/`nix develop`
while iterating on the plugin (compiling it directly, a dev shell with
`clang-tools`/`compile_commands.json` for editor tooling), reusing the same
nixpkgs the root flake already has — not pinning a second one. It is
deliberately *not* how the real system build wires this plugin in:
`Nixos/modules/hyprland/plugins/default.nix` references it via a plain local
path (`src = ../../../../Hyprland/plugins/canvas`), because building against
`pkgs.hyprland.stdenv` from *that* single nixpkgs evaluation is what
guarantees ABI/compiler-flag match with the exact locally-pinned Hyprland —
a second flake input here could drift and reintroduce the exact class of bug
that broke hypr-canvas in the first place.

## Manually invoking dispatchers via `hyprctl` for testing (no keybinds wired yet)

`hyprctl dispatch "hl.plugin.canvas.toggle()"` (parens, calling the function
immediately) is what an earlier session of this plugin's development
confirmed working — that stopped working at some point since (a Hyprland/Lua
wrapper behavior change, not a change on this plugin's side): `hl.dispatch`
now requires its argument to itself evaluate to a *dispatcher* — a plain Lua
function reference or an `hl.dsp.*`-constructed object — not the *result* of
calling one. A parenthesized call passes back whatever the function
returned (nothing, for a `void`-returning plugin action), and `hl.dispatch`
rejects that with `hl.dispatch: expected a dispatcher`. Confirmed by reading
`hlDispatch`/`pushDispatcherFunction` in
`src/config/lua/bindings/LuaBindingsToplevel.cpp` +
`LuaBindingsDispatcherUtils.cpp`: `lua_isfunction(L, idx)` is accepted
as-is, calling it itself internally.

The current working forms:
- No-arg action: `hyprctl dispatch "hl.plugin.canvas.toggle"` (bare function
  reference, no parens).
- Actions that take an argument need a zero-arg wrapper closure instead,
  since `hl.dispatch` always calls the dispatcher with 0 arguments:
  `hyprctl dispatch 'function() hl.plugin.canvas.zoom("out") end'`.
- Dispatchers act on "the workspace of whichever monitor the cursor is
  over" — for reliable multi-monitor testing, move the cursor there first
  with a *real* `hl.dsp` dispatcher (these are hand-written native bindings,
  unaffected by the above):
  `hyprctl dispatch "hl.dsp.cursor.move({x=1280,y=800})"`, then check with
  `hyprctl cursorpos`.

## Manual validation performed this session (original)

- `hyprctl plugin load`/`plugins list` — loads cleanly, no version-mismatch
  notification.
- Toggle, zoom (`zoom("out")`), pan (`pan("right")` × 3) — confirmed via
  screenshot: windows correctly shrunk/repositioned, fully readable, no
  corruption *at the time* (this predates the render-modifier order bug and
  the decoration-desync bug both found and fixed in the follow-up session
  below — those regressions/gaps weren't visible yet at this shallower level
  of testing).
- Existing windows floated on toggle-on — confirmed via `hyprctl clients`
  (`floating: 1`).
- New window placement — confirmed via file-based logging
  (`/tmp/canvas-debug.log`, since removed) that `Config::Actions::move`'s
  goal was set correctly and, after Hyprland's own centering logic settled,
  the window's real position converged exactly to the intended cursor-based
  canvas coordinate.
- **Not yet tested**: `panDrag` (mouse-drag pan) and scroll-wheel zoom
  bindings — no keybinds have been wired yet (deliberately; see below),
  these dispatchers exist and are logically identical to `pan`/`zoom` but
  haven't been exercised via an actual `bindm`/scroll config line.

## Manual validation performed in the bugfix follow-up session

User-reported symptoms this session: zoomed-out windows showed a large
unscaled/mispositioned "glass pane" outline around correctly-scaled content,
and clicking near a window's visible edge would trigger a wildly
disproportionate resize instead of a move. Root-caused and fixed (see
"Window decorations don't respect the canvas transform" and the
render-modifier-order fragility-ledger row above), then re-verified live via
`grim` screenshots on the real running compositor (not just `hyprctl` state):

- Zoom + pan combined (previously untested *together* at a non-1:1 scale) —
  confirmed via screenshot: a single, cleanly-scaled, correctly-positioned
  content rectangle, no stray outline, no double-scaled pan drift.
- Toggle-off restores decoration — confirmed via screenshot: border returns
  after `setProp("decorate", "unset", w)`.
- New window opened *while* canvas mode is already active on that
  workspace — confirmed via screenshot: opens undecorated (no glass-pane
  artifact) and placed correctly, exercising `WindowPlacement.cpp`'s
  decorate-off call specifically (a separate code path from the toggle-time
  sweep).
- `panDrag` and scroll-wheel zoom: still not exercised (still no keybinds
  wired — unchanged from before).

A further robustness pass (not a reported symptom, found by reviewing the
two fixes above for edge cases) turned up and fixed the
`window.moveToWorkspace` decoration-orphaning gap described in
`WindowPlacement`/the fragility ledger above:

- The move mechanics themselves — confirmed via `hyprctl clients`: a test
  window's `workspace:` field does change when moved via
  `hl.dsp.window.move({workspace = ...})`.
- The decoration-restore specifically — **not independently confirmed via
  screenshot**. Blocked by `hyprctl`'s Lua-dispatch wrapper being finicky
  about moving a window *off* a special workspace during this manual test
  (a testing-tool/methodology limitation hit while constructing the test
  case, not an error or crash from the plugin itself). The fix calls the
  identical `Config::Actions::setProp("decorate", ..., w)` already
  screenshot-verified working above, from the same `Event::bus()->m_events`
  subscription pattern already proven for this plugin's other two
  listeners, and compiled clean against the real Hyprland dev headers —
  high confidence, but flagged here as the one change this session that
  didn't get the same live pixel-level confirmation as the rest. Worth a
  real screenshot check next time this plugin is touched: toggle canvas on
  a workspace, open a window there, move it to a plain workspace with a
  normal keybind, confirm the border visibly returns.

## Not yet done

- No default keybinds wired (`Config/Binds/plugins.lua`) — deliberately, the
  user should choose the exact modifier/keys once this is confirmed stable.
- Plugin is not wired into any autostart-triggered activation — loading it
  is a manual `hyprctl plugin load` step for now, and no workspace starts in
  canvas mode automatically, per explicit instruction during testing.
