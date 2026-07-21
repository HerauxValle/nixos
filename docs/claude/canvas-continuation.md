# canvas plugin — continue right here

&desc: "Full session log + exact next steps for the canvas Hyprland plugin -- read this FIRST in any new chat before touching the plugin again."

**Read this whole file before doing anything else in a new chat about the canvas plugin.**
It contains everything discovered in the session that built this (2026-07-20/21, ~12:23 AM
finish), including bugs that took hours to isolate. Re-deriving any of this would waste a lot
of time and tokens. If something here looks stale, verify against the current code before
trusting it — but start by trusting it.

## TL;DR — where things actually stand right now

**Working, verified live via screenshots and logs:**
- Per-workspace infinite canvas: each workspace has its own independent pan/zoom camera
- Toggle canvas mode on/off for the workspace under the cursor
- Existing windows float automatically when a workspace enters canvas mode
- New windows opened while canvas mode is active float and appear at the cursor's canvas position
- Zoom (scroll wheel) anchors on the cursor, not a fixed corner
- Pan (keyboard arrows, and right-click-drag) works
- The quickshell bar / wallpaper stay fixed and don't zoom with window content
- All of this is wired to real keybinds (`mainMod + SHIFT + ...`), not just manual dispatch calls

**Known, not-yet-fixed gap (confirmed live, described precisely by the user without knowing
the internals):**
- The render transform is **visual only**. It changes how a window's pixels are drawn, but
  never touches the window's real `m_realPosition`/`m_realSize`. So while zoomed out:
  - Clicking a window targets its **real, unshrunk** position, not where it visually appears
  - The window's border/decoration is sized from the real (unscaled) geometry, so it visibly
    extends past the shrunk content
  - A window can still be "really" positioned off on a second monitor even though its shrunk
    render only shows on one
  - This is exactly the "Phase 2: click-to-focus / hit-testing" gap already called out in
    `Hyprland/plugins/canvas/DESIGN.md` — solving it needs a *second* kind of hook (remapping
    cursor→window resolution), which is genuinely bigger/riskier and was deliberately not
    attempted blind tonight.

**This is the next thing to work on.** See "Exact next steps" near the bottom.

## Live system state as of session end (verify before trusting — time has passed)

- Plugin is built and **loaded** (`hyprctl plugins list` should show `canvas by herauxvalle`).
  If not: `hyprctl plugin load ~/.local/share/hypr-plugins/canvas.so`
- It is **wired into the real Nix system config** already — `nixos-rebuild switch` builds and
  deploys it like any other part of the system. It is NOT in any autostart-triggered
  *activation* path (loading a fresh Hyprland session does auto-load the `.so` via the existing
  generic `autostart.lua` loop that loads every file in `~/.local/share/hypr-plugins/*.so` —
  that's pre-existing, harmless, and out of scope to change — but nothing auto-*toggles* canvas
  mode on for any workspace).
- Keybinds are live in `Hyprland/Config/Binds/canvas.lua`, required from `hyprland.lua`.
- Canvas mode's on/off state per workspace is **not persisted** — it's plain in-memory plugin
  state, resets to "off everywhere" every time the plugin (re)loads.
- Last live check (right before writing this doc) showed 2 windows, both `floating: 0` — canvas
  mode is very likely OFF right now on both workspaces. If anything seems stuck, `mainMod + SHIFT
  + C` toggles it for the workspace under the cursor, or fully bail out with
  `hyprctl plugin unload ~/.local/share/hypr-plugins/canvas.so`.

## The whole story, in order (so you understand *why*, not just *what*)

### 0. What the user actually asked for originally

`https://github.com/aaronsb/hypr-canvas` — zoom out to see all windows, pan around, zoom back
in, "like Google Maps for your desktop." User assumed it wasn't a real Hyprland plugin (why
`pacnix plugins <url>` failed) — it actually is a real plugin (C++ `.so`, hooks Hyprland
internals), but `pacnix plugins` (the repo's own plugin-scaffolding script) only knew how to
detect CMake/meson library names, not a bare Makefile, so it bailed. **Fixed pacnix plugins
first** (separate, already-done piece of work this session, unrelated to the bugs below — it
now detects plain-Makefile plugins too, reads `PLUGIN_NAME`, generates a generic installPhase).

Tried wiring up the real hypr-canvas plugin via the (now-fixed) pacnix script and by hand. **It
does not compile** against this system's Hyprland 0.55.4: its pinned commit hooks a class called
`CHyprRenderer`, which Hyprland has since renamed to `Render::IHyprRenderer`. hypr-canvas has no
version tags/branches (13 linear commits, alpha, single dev) — nothing to fall back to. This is
the whole reason a first-party rewrite happened at all.

### 1. First design: a genuine Hyprland plugin, `Hyprland/plugins/canvas/`

Planned via a real plan-mode session (see `git log`/the actual plan file if it still exists at
`~/.claude/plans/starry-sprouting-truffle.md` — may or may not survive across chats, don't rely
on it, this doc supersedes it). Original plan: **multi-workspace grid** — one hook
(`renderAllClientsForWorkspace`) fanned into many calls, one per grid slot, to show *every*
workspace on a monitor simultaneously like a wall of thumbnails.

**This grid approach was built, tested live, and found to be fundamentally broken:**
- First symptom: toggling it on showed a gray/blank primary monitor. Root cause found: `toggle()`
  alone never touched zoom, so the grid rendered at scale 1.0 — grid slots a full monitor-width
  apart don't overlap the visible viewport at all with no zoom applied, so only whichever
  workspace happened to land in the on-screen slot (usually empty) showed anything.
- Fixed that (auto-fit zoom on activation), rebuilt, retested. **Different failure**: "gray and
  black squares where the windows were."
- Root cause (found by reading the *real* `Renderer.cpp` source, not just headers — fetched from
  `https://raw.githubusercontent.com/hyprwm/Hyprland/v0.55.4/src/render/Renderer.cpp`):
  `IHyprRenderer::shouldRenderWindow()` gates whether a window renders on
  `CWorkspace::isVisible()` — a real compositor flag reflecting whether a workspace is *actually*
  the one switched-to on its monitor, not whichever workspace happens to get passed into
  `renderAllClientsForWorkspace`. **Structurally, a window on a non-active workspace will not
  render this way, no matter what translate/scale is used.** This is why the grid approach is a
  dead end without a much bigger, more invasive hook (forcing workspace visibility state during
  each grid slot's render, touching a lot more compositor state).

### 2. The pivot: ComfyUI-inspired per-workspace canvas (the user's own reframe)

User's insight: don't show multiple workspaces glued together — model it like ComfyUI's infinite
node canvas. **Each workspace is its own independent infinite 2D space**; windows are like
nodes, placed anywhere (not confined to monitor pixel bounds); pan/zoom navigates *within one
workspace's own space*. This completely sidesteps the `isVisible()` dead end — there's only ever
ONE workspace being rendered (the real active one), just with floating windows free to sit at
canvas coordinates far outside normal screen bounds.

Design decisions made with the user at this point (their explicit answers):
- Canvas workspaces are **floating-only** (windows placed freely, not tiled/auto-arranged)
- New windows appear **at the cursor's current position** (not a fixed origin, not just "camera
  center") — matching "new ComfyUI node appears near your view"

### 3. Rebuilding around the new model — architecture

Full architecture is documented in `Hyprland/plugins/canvas/DESIGN.md` — **read that file, it's
authoritative and was kept up to date through most of this session** (may be slightly behind the
very last fixes below; this doc is the most current source for anything that conflicts).

Quick recap of the file layout:
```
Hyprland/plugins/canvas/
├── Makefile, DESIGN.md, flake.nix (dev-only, see DESIGN.md for why)
└── src/
    ├── main.cpp                      -- wiring only
    ├── hypr/                         -- Hyprland-facing, the fragile layer
    │   ├── VersionGuard.{hpp,cpp}    -- __hyprland_api_get_hash() check
    │   ├── RenderHook.{hpp,cpp}      -- THE render hook(s), see below
    │   ├── Dispatchers.{hpp,cpp}     -- toggle/zoom/pan/panDrag/reset
    │   └── WindowPlacement.{hpp,cpp} -- window.open EventBus listener
    └── canvas/                       -- pure logic, zero Hyprland #includes
        ├── CanvasState.{hpp,cpp}     -- per-workspace pan/zoom state machine
        └── Transform.{hpp,cpp}       -- camera math + its inverse
```

### 4. Every bug found and fixed, in the order discovered (READ THIS CAREFULLY)

**Bug: `hyprctl dispatch <dispatcher> <args>` (classic syntax) doesn't work on this system at
all.** This system's Lua config wraps the `dispatch` hyprctl command itself, expecting a Lua
expression (`hl.dispatch(hl.dsp.window.close())`), not `dispatcher arg` text. Confirmed: even
`HyprlandAPI::invokeHyprctlCommand("dispatch", "setfloating address:... 1")` **from inside the
plugin's own C++ code** hit the exact same wrapper and failed identically (silently — nothing
checked the returned error string at first). **The actual correct way to call things from CLI on
this system**: `hyprctl dispatch "hl.plugin.canvas.toggle()"` (a full Lua expression as the
argument). This will still print a cosmetic error afterward (`hl.dispatch: expected a dispatcher`)
because the outer `hl.dispatch(...)` wrapper doesn't like receiving what our function returns —
**ignore that error, the inner call already ran**.

**Fix for the plugin's own C++ code**: don't use `invokeHyprctlCommand` at all for
`setfloating`/`move`/etc. Instead call `Config::Actions::floatWindow(...)` and
`Config::Actions::move(...)` directly (`#include <hyprland/src/config/shared/actions/ConfigActions.hpp>`,
ships in dev headers). This is the same internal layer *every* dispatcher path (legacy string,
Lua `hl.dsp.*`) ultimately calls into — bypasses both the legacy table and the Lua wrapper
entirely, works regardless of config mode. This is now how `Dispatchers.cpp` and
`WindowPlacement.cpp` do all window floating/moving.

**Bug: `hl.plugin.<name>.<dispatcher>()` (the real, working Lua bind convention on this system)
requires `HyprlandAPI::addLuaFunction`, not (only) `addDispatcherV2`.** Confirmed by testing
against the already-loaded `scrolloverview` plugin. The plugin registers **both** (`addDispatcherV2`
for legacy-config compatibility, `addLuaFunction` for this system's actual Lua binds) — see
`Dispatchers::registerAll`.

**Bug: `{ mouse = true }` in an `hl.bind(...)` options table is read by NOTHING.** Traced the real
Hyprland Lua binding source (`src/config/lua/bindings/LuaBindingsToplevel.cpp`, `hlBind`
function) — the options-table parser reads `repeating`/`locked`/`release`/`click`/`drag`/etc. but
never reads a `mouse` field at all. `kb.mouse` is only ever *checked* (for an exclusivity
validation against `repeat`/`release`/`locked`), never *set* by the Lua layer. **This doesn't
actually break anything** — traced `CKeybindManager::onAxisEvent`/`onMouseEvent` (the real
dispatch code) and confirmed they match binds purely by the literal key string
(`"mouse_up"`/`"mouse_down"`/`"mouse:273"`) against modmask, not by the `mouse` boolean at all.
So `{ mouse = true }` in the canvas binds is harmless-but-pointless — left in the bind file
for documentation clarity, doesn't need removing, doesn't need fixing.

**Bug (investigated, then found to be a non-issue): assumed mouse-drag binds only fire on
press+release, not continuously.** This was a real concern raised mid-session — turned out to be
wrong. **Confirmed via file-based logging** (`/tmp/canvas-debug.log`, temporary, since removed
from the code) that both `luaZoom` (scroll) and `luaPanDrag` (drag) genuinely get invoked
multiple times during actual scroll/drag gestures. Both callbacks fire correctly. **If drag-pan
ever seems totally inert again, this is NOT the first thing to suspect** — re-add temporary
`dlog()`-style file logging (pattern: `std::ofstream f("/tmp/canvas-debug.log", std::ios::app); f
<< msg << "\n";` inside the suspect callback) before assuming it's not firing; screenshots have
bad timing for catching transient notifications, file logs don't.

**Bug: new windows opened while canvas mode is active got centered on the monitor instead of
placed at the cursor.** Confirmed via logging that `Config::Actions::move()`'s *goal* was set
correctly immediately, but Hyprland's own initial floating-window centering logic runs shortly
after `window.open` fires and overwrote it. **Fix**: a 50ms deferred `CEventLoopTimer`
(`#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>` +
`<hyprland/src/managers/eventLoop/EventLoopManager.hpp>`, `g_pEventLoopManager->addTimer(...)`)
lets Hyprland's own centering settle first, so the plugin's own placement is the last word. See
`WindowPlacement.cpp`'s `onWindowOpen`. **If new-window placement breaks again, first suspect is
this timing race, not the position math.**

**Bug: `g_pInputManager->getMouseCoordsInternal()` returns *global* desktop coordinates, not
monitor-relative ones.** Confirmed via the real source
(`CInputManager::getMouseCoordsInternal() { return g_pPointerManager->position(); }` — matches
`hyprctl cursorpos`'s own coordinate space, i.e. spans every monitor's own layout offset in one
flat space, e.g. a monitor at global position (0, 360) means a cursor at (100, 400) on that
monitor reads as global (100, 400), not (100, 40)). But the render hook's translate/scale (and so
the whole canvas coordinate convention) is **monitor-relative** (matching how
`renderAllClientsForWorkspace`/`renderWorkspaceWindows` themselves operate on a `{0,0}`-origin
box for their own monitor). **Every place that reads the cursor must subtract
`monitor->m_position` first** before feeding it into `Transform::screenToCanvas`, and add it back
before feeding a result into `Config::Actions::move()` (which is itself global-coordinate, same
as window positions in general). See `cursorLocal()` in `Dispatchers.cpp` and the equivalent
inline logic in `WindowPlacement.cpp`'s `placeOnCanvas`. **This exact global-vs-local mismatch
bit us more than once — if any future coordinate math looks subtly wrong (off by a monitor's
offset, e.g. windows land in roughly the right spot but shifted), check this first.**

**Bug (biggest one, required a full architecture change): the multi-workspace-grid render hook
approach (see §1 above) is structurally broken because of `shouldRenderWindow`'s `isVisible()`
gate.** Already covered above — this is what triggered the whole pivot to the per-workspace
model in §2. Do not attempt the grid model again without first solving the workspace-visibility
problem (would need to temporarily force `CWorkspace::m_visible = true` — a plain public bool
member, confirmed via source, `isVisible()` is literally `return m_visible;` — around each
grid-slot's render call and restore it after; this was identified as a possible path but never
attempted, given the ComfyUI pivot made it moot).

**Bug: zoom always anchored on the canvas origin (top-left), not the cursor.** `zoomBy`/`zoomTo`
only ever changed `m_targetScale`, never adjusted pan to compensate — so zooming out always flung
window content toward a fixed corner and revealed a large "empty" (background-colored) canvas
void around it, which looked exactly like a rendering bug but wasn't. **Fix**: `zoomImpl` in
`Dispatchers.cpp` now computes the canvas point under the cursor *before* changing scale
(`Transform::screenToCanvas`), then re-derives `pan` after the scale change so that exact canvas
point ends up back under the cursor (`pan = anchorCanvas - cursorScreenPos / newScale`, using
`state.targetScale()` — a getter that had to be added to `CanvasState.hpp`, it only exposed
`currentScale()`, the eased value, before).

**Bug: the render-pass modifier (translate/scale) originally wrapped around
`renderAllClientsForWorkspace` in its entirety, which also wraps that function's own
background/layer-shell rendering — confirmed live, the user's quickshell bar was zooming/panning
right along with window content.** Traced the real `Renderer.cpp`: `renderAllClientsForWorkspace`
renders background + BACKGROUND/BOTTOM layer-shell surfaces, *then* calls one of
`renderWorkspaceWindows`/`renderWorkspaceWindowsFullscreen` (windows only — tiled/floating/pinned,
no layers), *then* renders TOP/OVERLAY layer-shell surfaces (where bars typically live) — all
within the same `CScopeGuard`-managed modifier scope. **Fix**: stopped hooking
`renderAllClientsForWorkspace` entirely. Now hooks the two narrower functions
(`renderWorkspaceWindows`/`renderWorkspaceWindowsFullscreen`) directly and pushes/pops the
`Render::SRenderModifData` modifier (via `CRendererHintsPassElement`,
`g_pHyprRenderer->m_renderPass.add(...)`) around *just* those calls — mirroring exactly the same
push/pop mechanism Hyprland's own code uses, just scoped tighter. This is now 2 hooks instead of
1, but each is narrower/more correct. **This fix is confirmed working live** — bar and wallpaper
stay fixed now.

**Known gap, not yet fixed (see TL;DR above): render-only transform doesn't move the window's
real position/size, so hit-testing/clicking and border-decoration sizing don't match the visual.**
This is what's next.

### 5. Nix wiring (already done, shouldn't need touching again unless the plugin itself changes)

- `Nixos/modules/hyprland/plugins/plugins.nix`: `mkPlugin` extended with an optional `src ? null`
  param — when set, uses that local path directly instead of `pkgs.fetchgit`, while still
  building against `pkgs.hyprland.stdenv` (this is what keeps ABI matched to the exact
  locally-pinned Hyprland — deliberately NOT wired as a second flake input like
  `Scripts/LTree`/`Casket`/`CRun`, which would risk a second, possibly-drifting nixpkgs pin).
- `Nixos/modules/hyprland/plugins/default.nix`: added the `canvas` entry —
  `src = ../../../../Hyprland/plugins/canvas`, `libFile = "canvas.so"` (Makefile's `OUT` has no
  `lib` prefix, matters for the `mkPlugin` default), `nativeBuildInputs = [ pkgs.pkg-config ]`
  (plain Makefile, no CMake, so `cmake` must NOT be in `nativeBuildInputs` or its setup hook
  tries and fails to configure a nonexistent `CMakeLists.txt`).
- `Hyprland/Config/Binds/canvas.lua` (new file, required from `hyprland.lua` at line ~43) — all
  the real keybinds, `mainMod + SHIFT + ...` (see that file directly, it's short and current).
- Also fixed, unrelated but same session: `Scripts/Pacnix/cmd/plugins.sh` now detects
  plain-Makefile plugins (reads `PLUGIN_NAME`, falls back to `nativeBuildInputs = [ pkg-config ]`
  only, generates a generic `find . -name '*.so' -exec cp` installPhase). Tested against the
  hypr-canvas URL directly and confirmed the detection logic itself works correctly (the actual
  build still fails, for the ABI-mismatch reason in §0, unrelated to the script).

### 6. Screenshots (in `docs/claude/screenshots/`, referenced from this session)

- `01-single-workspace-scale-proof.png` — very early test, BEFORE the ComfyUI pivot, proves the
  basic scale/translate render-pass-modifier mechanism works at all (editor+terminal correctly
  shrunk to ~50%, anchored top-left, fully readable, no corruption). This screenshot is what gave
  confidence to keep pursuing the render-hook approach after the multi-workspace-grid model broke.
- `02-existing-windows-floated.png` — confirms `Config::Actions::floatWindow` correctly floats
  pre-existing windows when a workspace enters canvas mode.
- `03-zoom-working-pre-cursor-anchor-fix.png` — zoom functioning (pre-cursor-anchor fix, so
  content is shrunk toward the corner, not the cursor — this is the "flew into the corner" bug
  described in §4, captured in the act).
- `04-pan-working-pre-cursor-anchor-fix.png` — pan functioning, same caveat as above.
- `05-clean-reset-state.png` — confirms `reset()` + `toggle()` off correctly returns the display
  to a completely normal state, no lingering artifacts.
- The user also sent phone-camera photos directly in chat (not saved as files I have access to)
  showing: (a) a lingering Lua-error notification banner (harmless, since dismissed via
  `hyprctl dismissnotify -1`), (b) the zoom-flying-to-corner bug very clearly on their actual
  monitor, (c) the current best-working state with multiple windows correctly shrunk/positioned
  and the border/hitbox-extends-beyond-visual bug visible as thin outline rectangles extending
  past each window's rendered content. If you need to re-see that exact bug, just toggle canvas
  on, zoom out, and take a fresh `grim` screenshot — it's fully reproducible.

## Exact next steps (in priority order)

1. **Confirm the current live state matches this doc** — `hyprctl plugins list`, `hyprctl clients`
   — things may have drifted if the user closed/reopened Hyprland, rebuilt, etc. since this was
   written.
2. **Decide whether to tackle Phase 2 (input/hit-test remapping) or ship as-is.** The honest
   trade-off to present: as-is, the plugin gives a fully working *visual* pan/zoom canvas (genuinely
   nice for organizing/viewing windows), but you must zoom back to 1:1 before clicking/interacting
   with a window (clicking while zoomed out targets the wrong, real position). This might be
   perfectly fine to ship as v1 and revisit later, or the user may want it solved now.
3. **If tackling Phase 2**: the concrete technical approach, not yet attempted or verified —
   - Need to intercept cursor→window resolution so a click while zoomed out correctly targets
     the *visually correct* window despite its real position/size being unchanged.
   - Candidate hook target (not yet confirmed, needs fresh investigation): something in
     `CCompositor`'s hit-testing (`vectorToWindowUnified` was seen referenced in
     `InputManager.cpp` at least once during this session's research — worth checking first) or
     in `CInputManager`'s pointer-motion/button handling path.
   - Alternative, possibly much simpler approach worth trying FIRST: instead of remapping hit
     ­testing, **actually move the real window** (`m_realPosition`/`m_realSize`, or via
     `Config::Actions::move`/`resize`) to match its visual position whenever the camera changes,
     rather than only changing how it's drawn. This would make clicking work "for free" since the
     window would really, truly be where it looks — but changes the render hook's role
     substantially (no longer a pure render-time modifier; becomes a live layout-manipulation
     system) and would need careful thought about interaction with Hyprland's own animation/
     `m_realPosition` easing, and about resetting windows back to sane real positions when canvas
     mode turns off. This wasn't attempted or even fully designed this session — treat it as a
     fresh idea to evaluate, not a proven direction.
   - Whichever direction: budget for another real live-testing cycle (rebuild → switch → reload
     plugin → test → screenshot/log, repeat). Each cycle this session took roughly 1-3 minutes for
     the Nix rebuild alone.
4. Once Phase 2 (or a decision to skip it) is settled, revisit `DESIGN.md`'s fragility ledger and
   add whatever new hook(s) get introduced, following the exact same table format already there.

## Useful commands for the next session (copy-paste ready)

```bash
# Check plugin is loaded
hyprctl plugins list

# Full reload cycle after any C++ change
timeout 300 nixos-rebuild build --flake /etc/nixos#herauxvalle
sudo nixos-rebuild switch --flake /etc/nixos#herauxvalle
hyprctl plugin unload /home/herauxvalle/.local/share/hypr-plugins/canvas.so
hyprctl plugin load /home/herauxvalle/.local/share/hypr-plugins/canvas.so

# The ONLY working way to call a plugin action from the CLI on this system
# (plain `hyprctl dispatch toggle` does NOT work here -- see bug log above)
hyprctl dispatch "hl.plugin.canvas.toggle()"
hyprctl dispatch "hl.plugin.canvas.zoom(\"in\")"
hyprctl dispatch "hl.plugin.canvas.pan(\"left\")"
hyprctl dispatch "hl.plugin.canvas.reset()"
# (each of these prints a harmless "hl.dispatch: expected a dispatcher" error
# afterward -- the actual call already ran before that error, ignore it)

# Dismiss lingering Lua-error notification toasts if the screen gets cluttered
hyprctl dismissnotify -1

# Screenshot a specific monitor (find names via `hyprctl monitors`)
grim -o DP-3 /path/to/out.png
grim /path/to/out.png   # all monitors, wide combined image

# Real keybinds (mainMod = SUPER on this system, defined in Config/Apps/defaults.lua)
# mainMod + SHIFT + C       toggle canvas mode
# mainMod + SHIFT + R       reset zoom/pan
# mainMod + SHIFT + arrows  pan (repeats while held)
# mainMod + SHIFT + scroll  zoom (down=in, up=out)
# mainMod + SHIFT + right-click-drag   pan by dragging
```

## Files to read, in order, when picking this back up

1. This file.
2. `Hyprland/plugins/canvas/DESIGN.md` — architecture + fragility ledger (authoritative for the
   "why" of every hook).
3. `Hyprland/plugins/canvas/src/hypr/RenderHook.cpp` — the current (narrower, 2-hook) render hook.
4. `Hyprland/plugins/canvas/src/hypr/Dispatchers.cpp` — zoom-to-cursor math, all the dispatcher
   logic.
5. `Hyprland/plugins/canvas/src/hypr/WindowPlacement.cpp` — new-window placement + the deferred
   timer.
6. `Hyprland/Config/Binds/canvas.lua` — the real keybinds.
