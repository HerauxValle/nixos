# Keybinds Feature Plan

## Architecture

### Data — BarConfig.qml (QML)
- 5 bind properties: `bindDrawer`, `bindLauncher`, `bindControlCenter`, `bindPower`, `bindSettings`
- Format: `"SUPER+SHIFT+B"` string. Empty string = unbound.
- Defaults: `SUPER+B`, `SUPER+Space`, `SUPER+C`, `SUPER+Escape`, `SUPER+comma`
- Persisted to `~/.config/mybar/theme.env` as `AETHERA_BIND_DRAWER`, `AETHERA_BIND_LAUNCHER`, `AETHERA_BIND_CC`, `AETHERA_BIND_POWER`, `AETHERA_BIND_SETTINGS`
- `_applyBind(action, bindStr)` — calls `hyprctl bind <mods> <key> global mybar:<action>` via queued Process (no overlapping hyprctl calls)
- `applyAllBinds()` — called from `Component.onCompleted` after the 1200ms ready timer fires
- `onBind*Changed` handlers → `_schedSave()` + `_applyBind()`
- Queue implemented as a JS array property; `onExited` on the Process drains it

### GlobalShortcuts — shell.qml (QML)
- Add `import Quickshell.Hyprland`
- 5 `GlobalShortcut` objects: `appid: "mybar"`, names: `"drawer"`, `"launcher"`, `"controlcenter"`, `"power"`, `"settings"`
- `onPressed` handlers call the appropriate ShellState/BarConfig toggle
- Remove the old `IpcHandler` blocks (replaced by GlobalShortcut)

### New Tab — BarSettings.qml (QML)
- Add `"KEYBINDS"` to `_tabs` array → tab index 4
- `BarConfig.openBarSettings(screen, 4)` navigates directly to it

### Keybinds Tab UI — BarSettings.qml (QML)
- Section header: `"OPEN"` (extensible — future sections go below)
- 5 rows, each: label left · keybind button right · reset arrow far right

#### Keybind button states
- **Idle**: shows formatted bind e.g. `"SUPER + B"`, or `"—"` if unbound. Normal border.
- **Capturing**: primary-coloured border, pulsing opacity, text `"Press keys…"`
- **Live** (keys held during capture): shows combo as it builds, e.g. `"SUPER + SHIFT + …"`
- **On all-keys-released** → commit, save, exit capture
- **ESC** → cancel, restore previous value
- **DEL** → clear to empty (unbound), save, exit capture

#### Reset arrow
- Visible only when current bind ≠ default for that action
- Fade in/out with `NumberAnimation` on opacity
- Click → restore default value (triggers save + apply automatically via onChanged)

#### Conflict highlight
- Computed JS check: for each bind, check if any other bind has the same non-empty string
- If conflict → button gets red border instead of normal border
- Evaluated reactively (binds are QML properties so bindings auto-update)

#### Key capture mechanism
- Transparent `Item` inside BarSettings with `focus: true` / `forceActiveFocus()` when capture starts
- `Keys.onPressed` → accumulate held modifiers + key into a working set
- `Keys.onReleased` → if the released key is non-modifier and all keys now up → commit
- `Qt.Key_Super_L/R` → `"SUPER"`, `Qt.Key_Shift_*` → `"SHIFT"`, `Qt.Key_Control_*` → `"CTRL"`, `Qt.Key_Alt_*` → `"ALT"`
- Regular key: formatted via `Qt.keyToString(key)` then capitalised
- Result stored as `"SUPER+SHIFT+B"`, displayed as `"SUPER + SHIFT + B"`
- BarSettings window already has `keyboardFocus: OnDemand` via Bar.qml

### Persistence
- Add 5 lines to `_buildContent()` in BarConfig
- Add 5 `_parseBind("AETHERA_BIND_*")` init properties with default fallback

### Startup
- `applyAllBinds()` fires from `BarConfig.Component.onCompleted` after ready timer (1200ms)
- No changes to `launch.sh` needed

## Not doing (yet)
- `hyprctl unbind` old bind before applying new one — Hyprland handles duplicate global binds gracefully
- Multiple sections beyond `"OPEN"` — structure is ready, content is one section for now
- Bind import from existing hyprland.conf — user sets them fresh in the UI
- Per-bind enable/disable toggle
