# Dolphin "Open With" never worked + Gwenview didn't match Dolphin's theme

## Summary

On this Hyprland (non-Plasma) NixOS setup, Dolphin's "Open With" dialog was
completely non-functional: right-click showed no candidate apps (or a
mis-categorized fallback tree at best), and double-clicking any
unassociated file did nothing at all. Separately, Gwenview didn't match
Dolphin's translucent look. Both had never worked correctly since the
NixOS install (not a regression) -- on the user's previous Arch install,
the same class of feature worked out of the box.

Root causes were several small, compounding, genuinely NixOS-specific gaps
-- nothing was "one bug." Fixed declaratively; no manual/imperative steps
remain. This took an enormous, disproportionate amount of back-and-forth
(~490k tokens) to actually pin down, mostly because several *real, correct,
verified* facts turned out to be irrelevant side quests, and the actual
answer for the Gwenview theming only fully surfaced after reading the
user's real, working Arch config as a source of truth instead of guessing.

## Environment

- NixOS + Hyprland (via UWSM), no Plasma session at all.
- Dolphin, Gwenview, kio-extras installed via `pkgs.kdePackages`.
- Kvantum (`Fluent-Dark` theme) + `qt6ct` for Qt widget theming
  (`QT_QPA_PLATFORMTHEME=qt6ct`, `QT_STYLE_OVERRIDE=qt6ct-style`).
- User config split across `Nixos/` (system + home-manager) and
  `Hyprland/` (Lua-based Hyprland config, symlinked in via home-manager).
- Reference: a mounted backup of the previous Arch install at
  `/run/media/herauxvalle/Media` (`pkg_explicit.txt`, `mimeapps.list`,
  `dolphinrc`, `kdeglobals`, and critically the real, working
  `Hyprland/Config/Apps/autostart.lua`/`autostart.conf`) -- this turned out
  to be the single most valuable piece of evidence in the whole
  investigation, and should have been checked much earlier.

## Symptoms

- Right-click a file -> "Open With": either a fully blank dialog (no
  apps, no tree, nothing) or, after a partial fix, a KDE-style categorized
  "browse every installed app" tree instead of a normal recommended-apps
  picker.
- Double-click a file with no configured default association: nothing
  happened. No dialog, no error, no launch.
- Affected *every* file type (markdown, images, PDFs, JSON, QML) --
  never app- or mimetype-specific.
- Separately: Gwenview's UI (sidebar, toolbar, image canvas) rendered as
  flat and opaque, unlike Dolphin's sidebar/toolbar, which show the
  desktop wallpaper blurred through them.

## Root causes

Several independent, compounding gaps -- all confirmed, not guessed,
by the time each was fixed:

1. **`/etc/xdg/menus/applications.menu` didn't exist at all.** NixOS
   ships no vendor menu file for the freedesktop.org XDG menu spec
   (Arch ships `arch-applications.menu`; Plasma ships
   `plasma-applications.menu`). Confirmed directly from Dolphin's own
   live log (`journalctl --user -t dolphin`):
   `"applications.menu" not found in QList("/etc/xdg/menus", ...)`.
   Dolphin's category-tree fallback view (and, as it turned out, some of
   the recommendation machinery) depends on this file existing.

2. **`kbuildsycoca6` (from the `kservice` package) was never on `PATH`.**
   It was only reachable via its full `/nix/store/...` path, because
   `kservice` was never explicitly listed as a package (only pulled in
   transitively as a dolphin/kio dependency, whose own `bin/` output
   doesn't get linked into the system profile). KIO's own internal
   cache-refresh logic looks up `kbuildsycoca6` via `PATH`, so this call
   silently failed every time.

3. **`kded6` does not run under Hyprland at all** (confirmed: no such
   process). Under a full Plasma session it auto-refreshes the KSycoca
   application/mimetype cache in the background; here, nothing does,
   so the cache only ever reflects whatever existed at some earlier,
   arbitrary point -- explaining why results were inconsistent across
   different sessions/launches, independent of which apps were actually
   installed at the time.

4. **Several apps genuinely weren't installed** that were present (and
   wired up) on the old Arch setup: `oculante` (image viewer), `gwenview`,
   `mpv`. Confirmed directly against the real Arch `pkg_explicit.txt` and
   `mimeapps.list` (which still referenced `oculante.desktop` as the
   image default, pointing at a package that was never actually
   installed on this NixOS system).

5. **nixpkgs' `vscode` package ships `code.desktop` with zero
   `MimeType=` entries.** Confirmed directly in
   `pkgs/applications/editors/vscode/generic.nix`: the `makeDesktopItem`
   call for the main desktop entry never passes `mimeTypes` (only the
   separate `code-url-handler.desktop`, for the `vscode://` scheme,
   gets one). This is a real, narrow nixpkgs packaging gap -- but not the
   actual fix that mattered here (see "ruled out" below).

6. **Kvantum's per-application theme registration only listed
   `dolphin`.** `Themes/Kvantum/kvantum.kvconfig`'s `[Applications]`
   section is what opts an app into Kvantum's `composite` /
   `translucent_windows` / `blur_translucent` features (all confirmed
   present and enabled in `Fluent-Dark.kvconfig`) -- Gwenview wasn't
   listed, so it didn't get them even though it nominally used the same
   theme via the `[General]` fallback.

7. **Gwenview's image-viewer canvas background is not styled via
   Kvantum/qt6ct at all.** Traced precisely through Gwenview's own
   source (`app/gvcore.cpp`): it builds its palette via
   `KColorSchemeManager`/`KColorScheme::createApplicationPalette()`,
   reading a KDE `.colors` scheme file directly -- a completely separate
   system from the Qt platform theme (`qt6ct`) that styles the
   sidebar/toolbar chrome. Stock `BreezeDark.colors` has zero alpha
   values anywhere in it, so no color-scheme *selection* alone could
   make that specific fill translucent, regardless of which scheme was
   active.

## Fix

All changes are declarative, live in the git-tracked dotfiles repo, and
require only a rebuild (no manual/imperative steps to reproduce).

**`Nixos/modules/desktop/desktop.nix`** -- provide the missing menu file
(using a plain/generic one, not Plasma's -- see "ruled out" below):

```nix
environment.etc."xdg/menus/applications.menu".source =
  "${pkgs.garcon}/etc/xdg/menus/xfce-applications.menu";
```

**`Nixos/modules/packages/installed.nix`** -- added, under
`pkgs.kdePackages`:

```nix
kservice   # provides kbuildsycoca6, now reachable on PATH
gwenview   # image viewer
```

and under the general package list:

```nix
mpv        # video player, was installed on Arch
oculante   # image viewer, was installed on Arch
```

**`Nixos/home/apps.nix`** -- Gwenview's own per-app config, forced since
Gwenview had already written an imperative copy of its own:

```nix
"gwenviewrc" = {
  force = true;
  text = ''
    [General]
    BackgroundColorMode=DocumentView::Dark

    [UiSettings]
    ColorScheme=BreezeDarkTransparent
  '';
};

xdg.dataFile."color-schemes/BreezeDarkTransparent.colors".source =
  ../../Themes/Gwenview/BreezeDarkTransparent.colors;
```

**`Themes/Gwenview/BreezeDarkTransparent.colors`** (new file) -- a copy
of KDE's stock `BreezeDark.colors` with a real alpha channel added to
exactly one entry:

```ini
[Colors:View]
BackgroundAlternate=29,31,34
# 4th value is alpha (0-255) -- this is the canvas transparency to tune,
# see Nixos/home/apps.nix for how this scheme gets wired to Gwenview.
BackgroundNormal=20,22,24,15
```

(Traced precisely: with a dark scheme active and `Dark` mode selected,
`gvcore.cpp`'s branching logic doesn't swap/recompute colors -- it uses
this `View`/`BackgroundNormal` entry directly as the canvas fill color
via `painter->fillRect(rect(), palette().base())`, which honors alpha.)

**`Themes/Kvantum/kvantum.kvconfig`** -- register Gwenview for Kvantum's
translucency features, same as Dolphin already was:

```ini
[Applications]
Fluent-Dark=dolphin,gwenview
```

## Verification

- `which kbuildsycoca6` resolves on `PATH` (previously required the full
  `/nix/store/...` path).
- `journalctl --user -t dolphin` no longer logs
  `"applications.menu" not found`.
- Right-click "Open With" / double-click on any file type shows a real,
  populated app list instead of a blank dialog.
- Gwenview's sidebar, toolbar, and image canvas all show the blurred
  desktop wallpaper through them, consistent with Dolphin's own look.

## What was ruled out along the way

In the order tried, each with real evidence at the time, even where the
evidence turned out to be a dead end for *this* specific bug:

1. **Manually declaring `xdg.mimeApps.defaultApplications`** (home-manager)
   to set default apps per mimetype -- rejected: this reflects the
   *output* of a working recommendation system (KDE's "remember this
   choice" checkbox), not the mechanism itself. The user correctly pushed
   back that hand-authoring this end-state wasn't actually fixing
   anything.

2. **`xdg-desktop-portal-kde` missing** (matching KDE bug 466148,
   "Dolphin's Open With dialog doesn't work"/needs
   `org.freedesktop.impl.portal.desktop.kde`) -- installed it via
   `xdg.portal.extraPortals`; confirmed installed (D-Bus service file
   present) but made no observable difference. Left removed from the
   final config since it wasn't the actual cause here.

3. **Wrong menu-file prefix, several times over** -- first tried
   `hyprland-applications.menu` (matching `$XDG_MENU_PREFIX` as seen in
   an interactive shell), then a `nixos-`-prefixed one matching an
   *existing* autostart script's auto-detection logic. Dolphin's own log
   consistently showed it searching for the plain, unprefixed
   `applications.menu` regardless -- the shell's `XDG_MENU_PREFIX` env
   var was not representative of Dolphin's actual runtime environment.
   Matching the literal name from Dolphin's own log is what actually
   worked.

4. **Plasma's own `plasma-applications.menu`** as the menu file source --
   mechanically worked (populated the categorized app tree, verified via
   screenshot), but the user correctly identified this produces a
   KDE/Plasma-specific hand-curated category tree with duplicate entries
   (e.g. Steam under both "Games" and "Internet") that's wrong for a
   non-Plasma setup. Switched to XFCE's `garcon`-provided
   `xfce-applications.menu` instead -- simpler, generic, no KDE-specific
   inclusion/exclusion rules. (Confirmed via the real Arch backup: Arch
   had *no* menu file of this kind at all -- this entire mechanism is
   about the fallback "browse everything" view, not the actual
   recommendation engine, which is why Arch never needed it.)

5. **Missing KDE QML modules (`environment.pathsToLink` not including
   `/lib/qt-6/qml`)** as the cause of the blank Open With dialog, on the
   theory that the "recommended apps" view is QML/Kirigami-based --
   plausible, never verified either way, not applied in the final config.

6. **Stale/never-rebuilt KSycoca cache** -- real and relevant (see root
   cause #3 above), but chasing it directly by manually running
   `kbuildsycoca6` from an unrelated shell repeatedly wrote to a
   *different* environment-hashed cache file
   (`~/.cache/ksycoca6_en_<hash>=`) than the one Dolphin's real session
   actually reads, even when `$XDG_DATA_DIRS` looked identical between
   shells. Never fully root-caused why the hash differed; worked around
   by having the user run `kbuildsycoca6` in their *own* real terminal
   and, ultimately, by the autostart script (see fix) running it in the
   correct session context automatically.

7. **Raw KSycoca binary cache byte-scanning** (`strings -e l` for
   UTF-16LE app names/mimetypes) as a diagnostic technique -- gave
   contradictory results on separately-built, similarly-sized cache
   files and was abandoned as unreliable. `journalctl --user -t dolphin`
   (the app's own real log output) was the only trustworthy signal
   throughout.

8. **A hand-written VS Code `.desktop`/`xdg.desktopEntries` override**
   with an explicit `MimeType=` list -- technically correct (root cause
   #5 above is real and confirmed at the nixpkgs source level), but
   rejected by the user as "a workaround, not a fix" since it doesn't
   explain or address why *every* file type was affected, not just
   markdown/text. Not applied in the final config.

9. **Hyprland per-window `opacity`/blur rule targeting Gwenview's window
   class** -- considered as a blunt way to force translucency, not
   applied once the real Kvantum + KColorScheme mechanisms (root causes
   #6/#7) were identified and confirmed to work more precisely.

10. **A global `kdeglobals` `ColorScheme=` setting** -- `kdeglobals`
    didn't exist on this system at all; critically, the user's *real*
    Arch `kdeglobals` didn't set a `ColorScheme` either, ruling this out
    as "the" mechanism for anything.

11. **Adding alpha to the shared `qt6ct` custom palette**
    (`Themes/QT/qt6ct/style-colors.conf`, the `Base` role) -- a real,
    already-alpha-carrying value existed in that file already
    (`#80dfdfdf`, almost certainly the `PlaceholderText` role, unrelated
    to backgrounds). Added alpha to the `Base` role specifically on the
    theory that Gwenview's canvas reads it -- no visible effect,
    reverted. Root cause #7 explains why: Gwenview's canvas fill never
    reads this file at all.

12. **`[UiSettings] ColorScheme=BreezeDark`** in `gwenviewrc`, copied
    from Dolphin's own `dolphinrc` -- real and kept in the final config
    (it does drive Gwenview's overall color scheme, and matters for the
    sidebar/toolbar), but alone it wasn't sufficient for canvas
    transparency, since stock `BreezeDark.colors` has no alpha in it
    (root cause #7). The working fix required *also* creating a custom
    scheme file with alpha added.

13. **`KWindowEffects::enableBlurBehind()` calls in application source**
    as the explanation for Dolphin's translucent sidebar -- checked
    directly against Dolphin's actual upstream source
    (`nix build nixpkgs#kdePackages.dolphin.src`, grepped for
    `KWindowEffects`/`BlurBehind`): zero matches. Ruled out.

14. **Kvantum's `reduce_window_opacity`** setting in
    `Fluent-Dark.kvconfig` -- found to be `0` (disabled), not the
    mechanism. The theme's *separate* `composite=true` /
    `translucent_windows=true` / `blur_translucent=true` settings (still
    in the theme, unmodified) are what's relevant, gated by the
    `[Applications]` per-app registration (root cause #6 / the actual
    fix).

15. **Confusion over `imv` vs `oculante`** as the "real" Arch image
    viewer -- checked the real Arch `pkg_explicit.txt`: both were
    installed, but only `oculante` was wired up in `mimeapps.list` as
    the actual default. `imv` was added, then removed again per the
    user's decision, once `oculante` was confirmed as the one that
    mattered.

## Diagnostics used

```
# The single most reliable signal throughout -- Dolphin's own real log
journalctl --user -t dolphin --since "5 minutes ago" --no-pager | grep -iE "offers|applications.menu"

# Verbose run, if the above isn't enough detail
QT_LOGGING_RULES="*.debug=true" dolphin

# Force a full KSycoca rebuild (run from the *actual* session, not an
# unrelated shell -- see root cause #3 / ruled-out #6 above)
kbuildsycoca6 --noincremental

# Live compositor state, instead of inferring from config files
hyprctl clients -j
hyprctl -j getoption decoration:blur:enabled

# Read real upstream source instead of guessing at behavior
nix build nixpkgs#<pkg>.src --no-link --print-out-paths
```

Comparing directly against the user's real, working Arch backup (once
mounted) was, in the end, far more valuable than any amount of local
guessing:

```
cat /run/media/.../Media/pkg_explicit.txt      # what was actually installed
cat /run/media/.../Media/Home/.config/mimeapps.list
cat /run/media/.../Media/Home/.config/dolphinrc
cat /run/media/.../Media/Home/.config/kdeglobals
cat /run/media/.../Media/Home/Dotfiles/Hyprland/Config/Apps/autostart.lua
```

## Lessons for next time

- The real Arch config backup should have been checked *first*, not
  after dozens of local theories. It directly contained the working
  reference implementation (the autostart cache-rebuild snippet) and
  ruled out several theories (Plasma menu files, `kdeglobals`
  `ColorScheme`) in seconds that took a long time to rule out by local
  guessing instead.
- When an app's visual behavior doesn't match another app using
  "the same theme," don't assume both read theming from the same place
  -- read the actual source (`gvcore.cpp` vs whatever styles Dolphin's
  chrome) before touching config files.
- A diagnostic technique that gives contradictory results on repeat
  (the raw KSycoca byte-scanning) should be dropped immediately, not
  reused "just in case."
