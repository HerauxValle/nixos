# Motion tuning: FloatingVM-matched gaps + research-backed animation curves

## Summary

Two related changes to how the desktop feels in motion, done in the same
pass since both were about making the tiling (scrolling) layout and
FloatingVM feel like one coherent system instead of two different tools
bolted together:

1. **Gaps** -- Hyprland's general `gaps_in`/`gaps_out` (used by every
   layout, including the scrolling/PaperWM-style one) now render at the
   same visual size as FloatingVM's own window-to-window/window-to-edge
   gap, instead of the arbitrary 5px/20px that shipped before.
2. **Animations** -- every Hyprland animation curve and duration, plus a
   new kitty cursor-trail animation, were replaced with values grounded in
   Material Design 3's published motion system and Jakob Nielsen's
   response-time research, instead of hand-picked numbers.

Files touched:

- `Hyprland/Config/UI/theme.lua` -- gaps, curves, animation durations
- `Hyprland/Config/Reactive/windowMode.lua` -- one animation leaf
  (`workspaces`) that lives outside `theme.lua` because it's specific to
  scrolling-layout mode
- `Kitty/kitty.conf` -- `cursor_trail` and its two related settings

## Part 1: Matching FloatingVM's gap

### Background

This system runs two window-management schemes side by side, toggled
independently:

- **FloatingVM** (`Hyprland/Floating/`, aka "hyprfloat") -- a custom
  floating-window manager. Snap/grid/center placement is computed in
  `Floating/modules/move.sh` and `Floating/modules/grid.sh`, both driven by
  a single config value, `WINDOW_GAP_PCT` (currently `2`, in
  `Floating/config/defaults.conf`), expressed as a **percentage of the
  monitor's smaller dimension**:

  ```bash
  gap = min(mon_w, mon_h) * gap_pct / 100
  ```

  On the main monitor (2560x1440, `min` = 1440): `1440 * 2 / 100 = 28.8`,
  floored/rounded to **28px**. This single `gap` value is used identically
  for the space between two floating windows in a grid *and* the space
  from a floating window to the screen edge -- FloatingVM doesn't
  distinguish the two the way Hyprland's native layouts do.

- **Hyprland's native layouts** (dwindle, master, and the built-in
  scrolling/PaperWM-style layout configured in
  `Config/Plugins/hyprscroll.lua` -- despite the filename, this is
  Hyprland's own `general:layout = scrolling`, not a separately loaded
  plugin) use two independent pixel values instead: `general.gaps_in`
  (between two tiled windows) and `general.gaps_out` (from a window to the
  screen edge).

Before this change, `theme.lua` set `gaps_in = 5, gaps_out = 20` --
values with no particular relationship to FloatingVM's 28px, so switching
between floating mode and the scrolling layout changed how "tight" the
window spacing felt.

### The fix, and the doubling gotcha

The naive fix -- set both `gaps_in` and `gaps_out` to `28` -- is wrong.
Hyprland renders `gaps_in` **twice** at a shared border, because each of
the two adjacent windows contributes its own `gaps_in` padding on its side
of the border. `gaps_out`, by contrast, only has one window contributing
to it (there's no window on the other side of a screen edge), so it
applies once.

That means, with `gaps_in = gaps_out = 28`, the border *between* two
windows visually renders at `28 + 28 = 56px` -- literally double the
`28px` gap from the outermost window to the screen edge. This was caught
visually (a screenshot of two side-by-side kitty panes made the mismatch
obvious) before it shipped.

The correct relationship, to make every visible gap actually equal:

```
gaps_in  = gaps_out / 2
```

### Final values (`Config/UI/theme.lua`)

```lua
hl.config({
    general = {
        gaps_in  = 14,   -- doubles to 28px at a shared border
        gaps_out = 28,   -- matches FloatingVM's WINDOW_GAP_PCT=2 on the
                          -- main 2560x1440 monitor
        ...
    },
})
```

### Known limitation

`WINDOW_GAP_PCT` is a *percentage*, computed live against whichever
monitor a floating window happens to be on -- so FloatingVM's actual gap
is ~28px on the main 2560x1440 monitor but only ~22px on the secondary
1920x1080 one (`1080 * 2 / 100 = 21.6`, rounded to even by `grid.sh` →
22). Hyprland's `gaps_in`/`gaps_out` are flat, global pixel values with no
per-monitor variant, so `14`/`28` matches the main monitor exactly and is
close-but-not-exact on the secondary. This was accepted as fine -- true
per-monitor parity would require either a monitor-aware `workspace_rule`
per output or a script that re-issues `hyprctl keyword general:gaps_*` on
monitor-focus-change events, which is more machinery than the visual
difference (28px vs 22px) justifies.

If `WINDOW_GAP_PCT` in `Floating/config/defaults.conf` ever changes, these
two values need to be recomputed by hand (`gaps_out = new_pct * 1440 /
100`, `gaps_in = gaps_out / 2`) -- there is deliberately no live
`hyprctl`/`jq` query wired into `theme.lua` to keep this in sync
automatically. Querying live monitor state synchronously during Lua
config parsing was tried and rejected: it's fragile (blocks config
loading on an external process, and the `hyprctl` socket isn't guaranteed
to be ready that early at compositor startup) and isn't a pattern used
anywhere else in this config. The one place this repo *does* read a value
from another file to avoid duplicating it is `Floating/sourceMe.lua`'s
`readConfigValue()` (reads `DEFAULT_WIDTH_PCT`/`DEFAULT_HEIGHT_PCT` out of
`Floating/config/defaults.conf`) -- that's the pattern to reach for if
this ever needs to be kept in sync programmatically, not a runtime
monitor query.

## Part 2: Animation curves and durations

### Why the old values were arbitrary

The previous `theme.lua` animation block was Hyprland's own example/stock
configuration values almost verbatim (e.g. `windows` at `speed = 7`,
matching the value in Hyprland's shipped default config), with a few
hand-tweaked outliers (`windowsOut = 1.49`, `zoomFactor = 7`). None of
these were derived from any stated reasoning -- they were whatever felt
roughly OK when the config was first written. The `workspaces` slide
animation in particular, at `speed = 13` (see below for units), was 1.3
**seconds** -- well past the point research on UI responsiveness
considers acceptable for a frequent, repeated action like switching
workspaces.

### The research basis

Two independent, well-documented sources were used instead of picking
numbers by feel:

1. **Google's Material Design 3 motion system**
   (m3.material.io/styles/motion) -- a set of published, user-tested
   easing curves and duration tokens used across Android/Chrome/every
   Google product. Two things from it were adopted directly:

   - **Curve shapes.** Real-world objects don't move at constant
     velocity -- they accelerate away from rest and decelerate into rest,
     because of inertia. M3 encodes this as named cubic-bezier curves:
     - `standard` -- `cubic-bezier(0.2, 0, 0, 1)` -- symmetric, for
       motion that doesn't have a clear "entering" or "exiting" character
       (a window being dragged/resized, a border color change).
     - `standardDecelerate` -- `cubic-bezier(0, 0, 0, 1)` -- eases out
       hard, for something appearing/entering.
     - `standardAccelerate` -- `cubic-bezier(0.3, 0, 1, 1)` -- eases in
       hard, for something disappearing/exiting.
     - `emphasizedDecelerate` -- `cubic-bezier(0.05, 0.7, 0.1, 1)` -- a
       stronger, more noticeable decelerate, reserved for less-frequent,
       more "significant" transitions (a whole window opening, not just a
       border blinking).
     - `emphasizedAccelerate` -- `cubic-bezier(0.3, 0, 0.8, 0.15)` -- the
       exit counterpart.

     M3 also defines a full `emphasized` (non-decelerate/accelerate)
     curve, but that one is technically a multi-segment spline in the
     spec, not a single cubic bezier -- Hyprland's `hl.curve()` only
     supports a single 4-point cubic bezier, so it was deliberately left
     out rather than faked with an inaccurate approximation.

   - **Duration bands.** M3 defines named duration tokens grouped into
     "short" (50-200ms), "medium" (250-400ms), "long" (450-600ms), and
     "extra-long" (700ms+) bands, with explicit guidance on which band
     fits which kind of motion:
     - *Short* is for small, frequent, low-attention motion -- a border
       highlighting, an icon fading. It has to stay fast because it fires
       constantly (every window focus change, for example) and any
       perceptible lag there compounds into a sluggish-feeling system.
     - *Medium* is for motion that covers real screen area and needs to
       be legible as motion, not just a jump-cut -- a window actually
       moving or resizing, a workspace swapping.
     - Longer bands exist for large, infrequent, "hero" transitions --
       not used here, since nothing in this config is that rare or that
       large.
     - **Exits are shorter than entrances.** This is explicit M3
       guidance: an appearing element can take a *bit* longer because the
       user is watching it arrive and forming an expectation; a
       disappearing element should get out of the way as fast as
       possible because the user has already moved on.

2. **Jakob Nielsen's response-time research** (Nielsen Norman Group,
   originally from *Usability Engineering*, 1993, still the standard
   reference for this) -- three thresholds for how humans perceive
   system response time:
   - **~0.1s (100ms)**: feels instantaneous: no separate "the system is
     doing something" perception forms.
   - **~1.0s**: the upper limit for keeping a user's flow of thought
     uninterrupted -- beyond this, users notice they're waiting.
   - **~10s**: the limit for keeping a user's attention on the task at
     all.

   This sets the outer bound: nothing in a desktop-interaction context
   (window move, workspace switch) should approach the 1-second mark,
   because every one of these animations happens many times per minute
   during normal use. M3's own "medium" band (250-400ms) already respects
   this with a comfortable margin -- which is part of why M3's bands were
   trusted as a starting point rather than picking durations from
   scratch.

### Unit conversion

Hyprland's `speed` field in `hl.animation()` is in **deciseconds** (1ds =
100ms) -- confirmed against the Hyprland wiki's Animations page, not
assumed. So M3's millisecond tokens divide by 100 to get Hyprland's
`speed` value: 150ms → `1.5`, 300ms → `3`, etc.

### Mapping (final values, `Config/UI/theme.lua`)

| Leaf | Old speed (ds → ms) | New speed (ds → ms) | Curve | M3 rationale |
|---|---|---|---|---|
| `global` | 10 → 1000ms | 3 → 300ms | `standard` | fallback only (every leaf below overrides it); medium band, symmetric |
| `border` | 5.39 → 539ms | 1.5 → 150ms | `standard` | fires on every focus change -- short band, symmetric (no enter/exit character) |
| `windows` | 7 → 700ms | 3 → 300ms | `standard` | actual spatial move/resize -- medium band, symmetric |
| `windowsIn` | 4.1 → 410ms | 2.5 → 250ms | `emphasizedDecelerate` | a window opening is a noticeable, infrequent event -- emphasized decelerate, low end of medium band |
| `windowsOut` | 1.49 → 149ms | 2 → 200ms | `emphasizedAccelerate` | exit, shorter than its matching entrance (250ms in, 200ms out) |
| `fadeIn` | 1.73 → 173ms | 1.5 → 150ms | `standardDecelerate` | lightweight opacity change -- short band |
| `fadeOut` | 1.46 → 146ms | 1 → 100ms | `standardAccelerate` | exit, shorter than its entrance (150ms in, 100ms out) |
| `fade` | 3.03 → 303ms | 2 → 200ms | `standard` | general/symmetric fade, short-to-medium boundary |
| `layers` | 3.81 → 381ms | 2 → 200ms | `standard` | bars/menus -- short band, needs to feel responsive |
| `layersIn` | 4 → 400ms | 1.5 → 150ms | `standardDecelerate` | popup/bar appearing |
| `layersOut` | 1.5 → 150ms | 1 → 100ms | `standardAccelerate` | popup/bar disappearing, shorter than its entrance |
| `fadeLayersIn` | 1.79 → 179ms | 1.5 → 150ms | `standardDecelerate` | same logic as `layersIn` |
| `fadeLayersOut` | 1.39 → 139ms | 1 → 100ms | `standardAccelerate` | same logic as `layersOut` |
| `zoomFactor` | 7 → 700ms | 3.5 → 350ms | `standard` | hyprexpo/scroll-overview zoom -- covers a lot of visual area, upper-medium band so it stays legible |
| `workspaces` (in `windowMode.lua`, scrolling-mode only) | 13 → 1300ms | 3.5 → 350ms | `standard` | full workspace swap -- upper-medium band; symmetric since it's the same motion both directions, not a one-way enter/exit |

Every removed line was left in place, commented out with an `-- old:`
prefix directly above its replacement, so the previous values are still
visible in-file for comparison/rollback without needing git history.

### The `windowMode.lua` gotcha

`Config/Reactive/windowMode.lua` sets its own `workspaces` animation
(used only when the scrolling layout is active, with a `slidevert`
style), and it referenced the `easeOut` curve that used to live in
`theme.lua`. Removing `easeOut` from `theme.lua` without checking for
other references would have left that line pointing at an undefined
curve. Fixed by giving `workspaces` its own `standard` curve and a
350ms/`3.5`ds duration -- see the table above.

## Part 3: Kitty cursor trail

Kitty's actual built-in animation feature is `cursor_trail` -- a fading
trail rendered behind the cursor as it moves, not something separate that
needed to be "enabled" from nothing (kitty doesn't animate window
resizing, tab switching, or anything else by default; this is the one
animatable surface it exposes). Added to `Kitty/kitty.conf`:

```
cursor_trail 150
cursor_trail_decay 0.1 0.2
cursor_trail_start_threshold 2
```

- **`cursor_trail 150`** -- max fade-out time in milliseconds. Same
  reasoning as the Hyprland "short" band above: 150ms is comfortably past
  Nielsen's ~100ms "instantaneous" threshold (so it's actually visible as
  motion) but well short of feeling like it lingers.
- **`cursor_trail_decay 0.1 0.2`** -- two floats, fastest and slowest
  fade time in seconds. Asymmetric on purpose (quick to start fading,
  slightly slower to fully vanish) rather than a flat linear fade, for
  the same real-world-deceleration reason the Hyprland curves are
  asymmetric.
- **`cursor_trail_start_threshold 2`** -- minimum cursor movement in
  cells before the trail triggers, filtering out sub-perceptual jitter
  from involuntary micro-movements.

## Verification

- Hyprland: `hyprctl reload`, then visually compare the gap between two
  side-by-side scrolling-layout windows against the gap from a window to
  the screen edge -- they should read as the same size. Toggle window
  focus/open/close/workspace-switch and confirm nothing feels like a
  jump-cut or a wait.
- FloatingVM: `Floating/main.sh --grid` with 2+ floating windows, compare
  the gap it renders against the scrolling-layout gap on the same
  monitor -- should match on the main 2560x1440 display.
- Kitty: open a new kitty window (config isn't hot-reloaded for
  `cursor_trail`; `allow_remote_control`-based live reload only affects
  already-open windows' *other* settings) and move the cursor -- a short
  fading trail should follow.

## What was considered and rejected

- **Setting `gaps_in = gaps_out`** -- visually doubles the between-window
  gap relative to the edge gap, due to Hyprland's border-doubling
  behavior. See Part 1.
- **Deriving the gap value live via `hyprctl monitors -j | jq` inside
  `theme.lua`** -- rejected as too fragile for a static config file (see
  the "Known limitation" note in Part 1).
- **M3's full `emphasized` curve** for `windowsIn`/`windowsOut` -- not
  used because it's a multi-segment spline in the actual spec, and
  approximating it as a single cubic bezier would misrepresent it as more
  rigorously sourced than it actually is. The decelerate/accelerate
  halves (which *are* single cubic beziers in the spec) were used
  instead.

## References

- [Material Design 3 -- Motion overview](https://m3.material.io/styles/motion/overview)
- [Material Design 3 -- Easing and duration](https://m3.material.io/styles/motion/easing-and-duration/tokens-specs)
- [Hyprland Wiki -- Animations](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/)
- [Nielsen Norman Group -- Response Times: The 3 Important Limits](https://www.nngroup.com/articles/response-times-3-important-limits/)
- [kitty documentation -- `cursor_trail`](https://sw.kovidgoyal.net/kitty/conf/)
