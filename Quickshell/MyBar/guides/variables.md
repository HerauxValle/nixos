# MyBar Environment Variables

All variables can be set in any `.env` file inside `~/.config/mybar/custom/`.
Files there are sourced last, so they override everything (theme, saved settings, defaults).

Copy `variables.env.example` from the repo into `~/.config/mybar/custom/` and edit it.

---

## Layout

| Variable | Default | Description |
|---|---|---|
| `AETHERA_MODE` | `hanging` | Bar style: `hanging` or `pill` |
| `AETHERA_POS` | `top` | Bar position: `top`, `bottom`, `left`, `right` |
| `AETHERA_ALIGN` | `center` | Pill alignment: `left`, `center`, `right` |
| `AETHERA_PILL_W` | `1.0` | Pill width as fraction of screen (0.35–1.0) |
| `AETHERA_MARGIN` | `0` (hanging) / `8` (pill) | Gap in px between screen edge and bar |
| `AETHERA_HEIGHT` | auto | Bar height in px |

## Appearance

| Variable | Default | Description |
|---|---|---|
| `AETHERA_OPACITY` | `0.72` | Bar/popup background opacity (0.4–1.0) |
| `AETHERA_UI_SCALE` | `1.0` | UI scale multiplier for all popups/drawer |
| `AETHERA_FONT_SIZE` | `12` | Bar widget font size in px |
| `AETHERA_TINT` | `0` | Accent preset index (0–5) |
| `AETHERA_ACCENT` | — | Custom accent hex color, e.g. `#5C8FA5` |

## Notifications

| Variable | Default | Description |
|---|---|---|
| `AETHERA_NOTIF_MAX` | `3` | Max simultaneous toast popups |
| `AETHERA_DRAWER_MAX` | `20` | Max notifications kept in drawer history |

## Airplane mode

| Variable | Default | Description |
|---|---|---|
| `AETHERA_AP_WIFI` | `1` | Disable WiFi in airplane mode (0/1) |
| `AETHERA_AP_BT` | `1` | Disable Bluetooth in airplane mode (0/1) |
| `AETHERA_AP_ETH` | `1` | Disable Ethernet in airplane mode (0/1) |
| `AETHERA_AP_DAEMONS` | `0` | Kill daemons in airplane mode (0/1) |
| `AETHERA_AP_FIREWALL` | `0` | Enable firewall in airplane mode (0/1) |

## Keybinds

Format: `MOD+MOD+KEY`, e.g. `SUPER+SHIFT+N`. Mods: `SUPER`, `CTRL`, `ALT`, `SHIFT`, `AltGr`.

| Variable | Default | Description |
|---|---|---|
| `AETHERA_BIND_DRAWER` | `SUPER+B` | Toggle sidebar |
| `AETHERA_BIND_LAUNCHER` | `SUPER+Space` | Toggle app launcher |
| `AETHERA_BIND_CC` | `SUPER+C` | Toggle control center |
| `AETHERA_BIND_POWER` | `SUPER+Escape` | Toggle power menu |
| `AETHERA_BIND_SETTINGS` | `SUPER+comma` | Open settings |
| `AETHERA_BIND_NOTIFICATIONS` | `SUPER+SHIFT+N` | Toggle notification panel |
| `AETHERA_BIND_WIFI` | `SUPER+SHIFT+W` | Toggle WiFi settings |
| `AETHERA_BIND_BLUETOOTH` | `SUPER+SHIFT+B` | Toggle Bluetooth settings |
| `AETHERA_BIND_WORKSPACEMENU` | `SUPER+Tab` | Toggle workspace menu |

## Keybind defaults

These set what the **reset arrow** in settings resets to, and the initial bind on first launch.
Copy `keybind_defaults.env` from the repo root to `~/.config/mybar/custom/` to override.

| Variable | Default | Description |
|---|---|---|
| `AETHERA_DEFAULT_DRAWER` | `SUPER+B` | Default bind for sidebar |
| `AETHERA_DEFAULT_LAUNCHER` | `SUPER+Space` | Default bind for app launcher |
| `AETHERA_DEFAULT_CC` | `SUPER+C` | Default bind for control center |
| `AETHERA_DEFAULT_POWER` | `SUPER+Escape` | Default bind for power menu |
| `AETHERA_DEFAULT_SETTINGS` | `SUPER+comma` | Default bind for settings |
| `AETHERA_DEFAULT_NOTIFICATIONS` | `SUPER+SHIFT+N` | Default bind for notification panel |
| `AETHERA_DEFAULT_WIFI` | `SUPER+SHIFT+W` | Default bind for WiFi settings |
| `AETHERA_DEFAULT_BLUETOOTH` | `SUPER+SHIFT+B` | Default bind for Bluetooth settings |
| `AETHERA_DEFAULT_WORKSPACEMENU` | `SUPER+Tab` | Default bind for workspace menu |

## Key capture timers

| Variable | Default | Description |
|---|---|---|
| `AETHERA_CAPTURE_TIMEOUT` | `3000` | ms before capture cancels if no input |
| `AETHERA_CAPTURE_GREEN_MS` | `1200` | ms the "saved" green flash shows |
| `AETHERA_CAPTURE_YELLOW_MS` | `1200` | ms the "add a key/modifier" warning shows |
| `AETHERA_CAPTURE_CONFLICT_MS` | `2000` | ms the "already bound" red shows |
