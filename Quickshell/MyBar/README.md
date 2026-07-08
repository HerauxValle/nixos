# Aethera Shell

A Quickshell/QML Wayland bar for Hyprland. Multi-monitor, themeable, fully keyboard-driven.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/HerauxValle/Aethera/main/main.sh)
```

This clones the latest release into `~/Projects/MyBar`, installs missing dependencies, compiles the C++ backends, and launches.

**Manual install** (if you already cloned):
```bash
bash ~/Projects/MyBar/main.sh --install
bash ~/Projects/MyBar/main.sh --launch
```

Autostart in `hyprland.conf`:
```
exec-once = bash ~/Projects/MyBar/main.sh
```

## Requirements

- [Quickshell](https://quickshell.outfoxxed.me/) 0.3.0+
- Hyprland
- `g++`, `pkg-config` (for compiling C++ backends)
- `nmcli`, `bluetoothctl`, `wpctl`/`pipewire`, `hyprctl`
- `libnm`, `qt6-base` (runtime libs — installed automatically by `--install`)

## Keybinds

Default binds registered automatically in Hyprland — no `hyprland.conf` edits needed.

| Bind | Action |
|---|---|
| `SUPER+B` | Toggle sidebar |
| `SUPER+Space` | Toggle app launcher |
| `SUPER+C` | Toggle control center |
| `SUPER+Escape` | Power menu |
| `SUPER+comma` | Advanced settings |
| `SUPER+SHIFT+N` | Notifications |
| `SUPER+SHIFT+W` | WiFi settings |
| `SUPER+SHIFT+B` | Bluetooth settings |
| `SUPER+Tab` | Workspace menu |

All binds are configurable in **Advanced Settings → Keybinds**.

## Customisation

Variables are read from env files sourced in this order (last wins):

1. `themes/<theme>.env` — built-in theme (default: `mountain`)
2. `~/.config/mybar/theme.env` — saved UI state (written automatically)
3. `~/.config/mybar/custom/*.env` — your overrides (highest priority)

Copy `variables.env.example` or `keybind_defaults.env` from the repo root into `~/.config/mybar/custom/` to override defaults.

See **`guides/variables.md`** for the full variable reference.

### Switch theme

```bash
AETHERA_THEME=default bash ~/Projects/MyBar/main.sh --launch   # Material You dark
AETHERA_THEME=mountain bash ~/Projects/MyBar/main.sh --launch  # Alpine blue (default)
```

## File map

```
MyBar/
├── main.sh                        entry point: --launch / --compile / --install / --uninstall
├── shell.qml                      Quickshell root: loads all modules, IPC handlers
├── variables.env.example          copy to ~/.config/mybar/custom/ to override vars
├── keybind_defaults.env           copy to ~/.config/mybar/custom/ to change default binds
├── config/
│   ├── BarConfig.qml              singleton: all settings, persistence, bind management
│   └── Colors.qml                 singleton: theme colors
├── modules/
│   ├── bar/                       PanelWindow per screen, pill rendering, auto-hide
│   ├── clock/                     clock widget
│   ├── dashboard/                 dashboard overlay
│   ├── drawer/                    left sidebar (essentials, dashboard, notifications tabs)
│   ├── indicators/                status indicators
│   ├── launcher/                  app launcher
│   ├── notifications/             toast popups + notification panel
│   ├── osd/                       on-screen display (volume, brightness)
│   ├── popups/                    control center, wifi, bluetooth, power, settings, etc.
│   ├── settings/                  advanced settings tab panels
│   ├── systray/                   system tray
│   ├── widgets/                   bar widgets (mpris, volume, network, cpu, memory, etc.)
│   └── workspaces/                workspace indicators
├── services/
│   ├── Audio.qml                  Pipewire/wpctl audio state
│   ├── Network.qml                WiFi + Bluetooth via nmcli/bluetoothctl
│   ├── NotificationService.qml    DBus notification listener
│   ├── OsdState.qml               OSD trigger state
│   └── ShellState.qml             global UI state (drawer open, launcher open, etc.)
├── source/
│   └── appscanner/                C++ binary: scans .desktop files for the launcher
├── themes/
│   ├── mountain.env               alpine blue-teal (default)
│   └── default.env                Material You dark
├── scripts/
│   ├── launch/launch.sh           sources env files, sets layerrules, starts qs
│   └── build/                     compile.sh / install.sh / uninstall.sh
└── guides/
    ├── variables.md               full AETHERA_* variable reference
    └── keybinds.md                keybind documentation
```
