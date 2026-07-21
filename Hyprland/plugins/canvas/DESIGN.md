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
  `Config::Actions::floatWindow` (see below).
- **`WindowPlacement`**: subscribes to the stable `EventBus`
  (`m_events.window.open`, `m_events.workspace.removed`) — no extra function
  hook needed for this, the event bus is Hyprland's own sanctioned pub/sub
  layer used throughout its codebase, not just by plugins. On `window.open`,
  if the window's workspace is in canvas mode, it schedules a short
  (50ms) deferred callback via `CEventLoopTimer` to float the window and move
  it to the cursor's canvas position.

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
| `Config::Actions::floatWindow`/`move` | `ActionResult floatWindow(eTogglableAction, std::optional<PHLWINDOW>)`, `ActionResult move(const Vector2D&, bool, std::optional<PHLWINDOW>)` | `hypr/Dispatchers.cpp`, `hypr/WindowPlacement.cpp` | Direct, config-mode-independent equivalent of the `setfloating`/`move` dispatchers — bypasses the Lua-config `dispatch` wrapper that broke `invokeHyprctlCommand` entirely on this system | If these functions are renamed/restructured, floating/positioning stops working (each call already checks its `ActionResult` and is safe to no-op on failure) | Re-check `src/config/shared/actions/ConfigActions.hpp` for the current function signatures |
| Version guard | `__hyprland_api_get_hash()` vs `__hyprland_api_get_client_hash()` | `hypr/VersionGuard.cpp` | Official idiom (matches `csgo-vulkan-fix`) — Hyprland's own loader already gates on this hash via `dlsym` per `PluginAPI.hpp`'s comments, so this guard's value is a friendlier, visible failure mode, not a hole Hyprland otherwise leaves open | n/a — this is Hyprland's own mechanism | Confirm both functions still exist with this shape before assuming the guard compiles |

## Non-goals / explicitly deferred

- **Click-to-focus / hit-testing while zoomed out**: clicking a window at its
  shrunk/panned position should focus it. Not implemented — needs its own
  investigation into how Hyprland resolves screen coordinates to a window
  for input purposes, which wasn't scoped in this session.
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

## Manual validation performed this session

- `hyprctl plugin load`/`plugins list` — loads cleanly, no version-mismatch
  notification.
- `hyprctl dispatch "hl.plugin.canvas.toggle()"` (this system's actual
  Lua-config calling convention — plain `hyprctl dispatch toggle` does not
  work here, since `dispatch` itself is wrapped to expect a Lua expression)
  — toggled canvas mode on/off correctly.
- Zoom (`zoom("out")`) — confirmed via screenshot: windows correctly shrunk
  and repositioned, fully readable, no corruption.
- Pan (`pan("right")` × 3) — confirmed via screenshot: both windows shifted
  correctly, fully readable.
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

## Not yet done

- No default keybinds wired (`Config/Binds/plugins.lua`) — deliberately, the
  user should choose the exact modifier/keys once this is confirmed stable.
- Plugin is not wired into any autostart-triggered activation — loading it
  is a manual `hyprctl plugin load` step for now, and no workspace starts in
  canvas mode automatically, per explicit instruction during testing.
