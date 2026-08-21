# How to theme a new app with Kvantum (Fluent-Dark)

## When this applies

Any Qt app (Qt5 or Qt6) you want to visually match Dolphin/Gwenview/Prism
Launcher. Doesn't apply to GTK apps (separate theming system) or apps that
ignore the platform Qt style entirely.

Worked example this guide is based on: `Nixos/config/software/programs/prism.nix`
(Prism Launcher). Read that file alongside this doc for a full real case.

## Background -- why this isn't just "set a color"

Dolphin's actual look (rounded corners, translucent/blurred panels, teal
accent) comes from **Kvantum's `Fluent-Dark` SVG theme**
(`Themes/Kvantum/Fluent-Dark/Fluent-Dark.kvconfig`), not from a `QPalette`
color scheme. `Themes/QT/qt6ct/style-colors.conf` is a real, separate
palette most apps use, but Kvantum draws its own widgets from SVG assets
and only falls back to that palette for the few things it doesn't skin
directly -- recoloring a *different* Qt style (Fusion, Breeze) will never
reproduce Kvantum's actual shapes, however close the colors are. See
`Documentation/Bugfixes/dolphin-openwith-and-gwenview-theming.md` for the
fuller investigation this was first discovered in.

Kvantum itself only renders as `Fluent-Dark` for apps explicitly listed
in `Themes/Kvantum/kvantum.kvconfig`'s `[Applications]` section --
everything else gets the system-wide fallback theme (`kvantum-dark`,
plainer). Getting a new app to *look like* Dolphin means both: (1) the
app is actually using the Kvantum Qt style plugin at all, and (2) it's
registered for `Fluent-Dark` specifically.

## Steps

### 1. Register the app for `Fluent-Dark`

Add the app's real executable basename (not its display name) to
`Themes/Kvantum/kvantum.kvconfig`:

```ini
[Applications]
Fluent-Dark=dolphin,gwenview,prismlauncher,your-new-app
```

Find the real basename with `readlink -f "$(command -v your-new-app)"` if
unsure -- Kvantum matches on the actual running binary's name.

### 2. Confirm the app can even load Qt platform theming

Check whether it already honors `QT_QPA_PLATFORMTHEME=qt6ct` /
`QT_STYLE_OVERRIDE` -- most native Qt apps do automatically. GTK apps,
Electron apps, and apps that hardcode their own style (rare) don't apply
here at all.

### 3. Make sure the Kvantum Qt style plugin is actually on the app's `QT_PLUGIN_PATH`

This is the step that's easy to skip and silently gets you Fusion instead.
Check the app's home-manager module for a `package` option -- if it
exists, override it the same way `prism.nix` does:

```nix
package = pkgs.<app>.overrideAttrs (old: {
  buildInputs = old.buildInputs ++ [ pkgs.kdePackages.qtstyleplugin-kvantum ];
});
```

This works because `wrapQtAppsHook`'s `qtHostPathHook` env-hook fires
automatically for every `buildInput` at build time and appends
`<pkg>/lib/qt-6/plugins` (or `/qt-5/plugins` for Qt5 apps -- use
`libsForQt5.qtstyleplugin-kvantum` instead) to `QT_PLUGIN_PATH` on its
own. No manual `wrapProgram`/`makeWrapper` call needed.

If the app has no home-manager `package` option to override (e.g. a
plain `environment.systemPackages` entry), the same `overrideAttrs`
pattern still applies -- just wrap it wherever the package is declared.

Verify after rebuild, don't assume:

```bash
strings "$(readlink -f "$(command -v your-new-app)")" \
  | grep -o '/nix/store/[a-z0-9]*-qtstyleplugin-kvantum[^ ]*'
```

If this prints nothing, the app isn't going to render as Kvantum no
matter what step 1 says.

### 4. If the app has its own separate theme-selection setting

Some apps (Prism Launcher, KDE apps with `kdeglobals`) have an
app-specific "which Qt style to use" setting independent of the system
default, and need telling explicitly. For Prism specifically this is
`programs.prismlauncher.settings.ApplicationTheme` pointing at a
`programs.prismlauncher.themes.<name>` entry whose own `theme.json` sets
`"widgets": "kvantum"` -- see `prism.nix` for the full working example,
including how its palette was pulled from
`Fluent-Dark.kvconfig`'s `[GeneralColors]` section rather than invented.

Most apps don't have this extra layer -- they just pick up `qt6ct`'s
global `style=kvantum-dark` setting automatically once step 3 is done,
with no per-app config needed at all.

### 5. Rebuild and check visually

```
pacnix rebuild
```

Then actually open the app and compare against Dolphin side by side --
rounded corners, translucent/blurred panels, and the teal `#5294e2`
accent are the tells that Kvantum is really rendering, not just a
recolored fallback style.

## Common failure mode

Getting *a* theme applied but the wrong shapes (e.g. Breeze's blocky
chevrons/borders with Kvantum-ish colors) means step 3 loaded the wrong
style plugin, or step 4's `"widgets"` value doesn't match the actual
`QStyleFactory` key the intended plugin registers under. This exact
mistake happened once already while theming Prism Launcher -- Breeze was
tried first, looked plausible, and was wrong.
