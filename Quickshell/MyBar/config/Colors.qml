pragma Singleton
import QtQuick
import Quickshell

// ── Color palette ─────────────────────────────────────────────────────────
// Alpine / mountain defaults.  Override any colour with AETHERA_* env vars.
// Use themes/mountain.env or themes/default.env — source them in launch.sh.
//
// Alpha hex format: #AARRGGBB  (e.g. #E1132433 = 88% opacity)
// Property names MUST NOT start with "on<Uppercase>" — QML treats those as
// signal handlers.  Text-on-surface colours are prefixed "col".
QtObject {
    function ec(key, fallback) {
        const val = Quickshell.env(key)
        return Qt.color(val || fallback)
    }

    // ── Surfaces — semi-transparent by default for iOS-style glass blur ──
    // Themes override via AETHERA_* env vars. Alpha format: #AARRGGBB.
    property color surface:              ec("AETHERA_SURFACE",          "#08141A")
    property color surfaceContainer:     ec("AETHERA_SURFACE_C",        "#0D1E28")
    property color surfaceContainerHigh: ec("AETHERA_SURFACE_CH",       "#152E3A")
    readonly property color surfaceContainerAlpha: ec("AETHERA_SURFACE_C_ALPHA", "#B80D1E28")
    // Popup bg — matches bar/drawer: surface color at barOpacity so blur bleeds through consistently
    property color popupBg:              ec("AETHERA_POPUP_BG",         "#D6081220")
    property color popupBorder:          ec("AETHERA_POPUP_BORDER",     "#28FFFFFF")

    // ── Accent ───────────────────────────────────────────────────────────
    // Priority: AETHERA_ACCENT (user-set) > AETHERA_PRIMARY (theme) > Hyprland border (set by BarConfig) > default
    property color _hyprAccent: "#00000000"   // set by BarConfig after hyprctl query
    property color primary: {
        const accent = Quickshell.env("AETHERA_ACCENT")
        if (accent) return Qt.color(accent)
        const theme = Quickshell.env("AETHERA_PRIMARY")
        if (theme) return Qt.color(theme)
        if (Colors._hyprAccent.a > 0) return Colors._hyprAccent
        return Qt.color("#5C8FA5")
    }
    property color colOnPrimary:               ec("AETHERA_ON_PRIMARY",     "#04141E")
    property color primaryContainer:           ec("AETHERA_PRIMARY_C",      "#0D6B85")
    property color secondaryContainer:         ec("AETHERA_SECONDARY_C",    "#1A3545")

    // ── Text ─────────────────────────────────────────────────────────────
    property color colOnSurface:        ec("AETHERA_TEXT",          "#EAF4F8")
    property color colOnSurfaceVariant: ec("AETHERA_TEXT_MUTED",    "#9EB5BF")

    // ── Borders / states ─────────────────────────────────────────────────
    property color outline:                ec("AETHERA_OUTLINE",    "#1E3A4A")
    property color outlineVariant:         ec("AETHERA_OUTLINE_V",  "#122530")
    readonly property color error:          ec("AETHERA_ERROR",      "#CF6679")

    // ── Animation curves — Aether Ridge spec: easeOutCubic, NO bounces ───
    // Spatial movement (popup reveal, position): 200ms
    readonly property var spring:   [0.33, 1.00, 0.68, 1.00]   // easeOutCubic — no overshoot
    // Subtle effects (opacity, color, scale): 160ms
    readonly property var standard: [0.33, 1.00, 0.68, 1.00]   // same curve, shorter duration
}
