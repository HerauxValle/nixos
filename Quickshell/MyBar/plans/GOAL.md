# MyBar — Architecture & Design Goals

## What MyBar Is

MyBar is a fully custom Wayland shell built on Quickshell and Qt/QML, targeting Hyprland on Arch Linux. It is not a configuration layer on top of an existing bar — it is a ground-up implementation of every shell surface: bar, drawer, control center, OSD, notification system, launcher, and settings panels. The design philosophy is that the shell owns its entire stack, with no dependency on external bar programs, status daemons, or notification servers.

---

## Stack

### QML — The UI Layer
QML is the sole rendering layer. Every visible surface — the bar, the drawer, the control center, popups, settings panels — is a QML component. QML contains no business logic, no system calls, and no IPC. It binds to properties exposed by the C++ layer and renders them. Animations, layouts, theming, and component composition live here and nowhere else.

### C++ — The State and Integration Layer
C++ owns all runtime state. Every piece of system information the shell displays — audio volume, network state, Bluetooth devices, media playback, CPU/memory/network throughput, display configuration, notification queue — is owned by a C++ `QObject` singleton or model registered to the QML engine. QML observes these via `Q_PROPERTY` bindings and signals. C++ never reads from QML; QML only reads from C++. The data flow is strictly unidirectional.

C++ also owns all D-Bus clients and Wayland protocol client implementations. There are no subprocess calls for system state that has a proper API:
- Audio state comes from a `libpipewire` client integrated into Qt's event loop via `QSocketNotifier`
- Bluetooth device state comes from a BlueZ D-Bus client (`org.bluez`)
- Network state comes from a NetworkManager D-Bus client (`org.freedesktop.NetworkManager`)
- Media player state comes from an MPRIS D-Bus client (`org.mpris.MediaPlayer2`)
- Notifications are served by a proper `org.freedesktop.Notifications` D-Bus service implemented as a Qt D-Bus adaptor
- Display management goes through the `wlr-output-management-unstable-v1` Wayland protocol client
- Brightness control goes through `logind` D-Bus or `wlr-gamma-control` — not `brightnessctl`

The C++ layer is built with CMake using `qt_add_qml_module` for type registration. All monitor binaries (`cpumonitor`, `memmonitor`, `netmonitor`, `appscanner`, `notifserver`) are targets in a single CMake project with proper dependency tracking.

### Rust — The Hyprland IPC Daemon
A standalone Rust binary built with `hyprland-rs` sits permanently on Hyprland's Unix event socket. It receives all Hyprland events — workspace changes, window focus, fullscreen state, monitor layout changes — and emits structured JSON onto a Unix socket. The QML layer reads this stream via Quickshell's `Process` API. This daemon is the single point of contact between the shell and Hyprland's event system. There are no `hyprctl` subprocess spawns for reactive state — those are reserved for one-shot dispatch commands only (e.g. moving a window, changing a workspace).

---

## Data Flow

```
Hardware / Kernel / Wayland compositor
        │
        ├── /proc/stat, /proc/meminfo ──────────► cpumonitor.cpp / memmonitor.cpp
        ├── rtnetlink socket ───────────────────► netmonitor.cpp
        ├── libpipewire event loop ─────────────► audio C++ singleton
        ├── BlueZ D-Bus ────────────────────────► bluetooth C++ client
        ├── NetworkManager D-Bus ───────────────► network C++ client
        ├── org.mpris.MediaPlayer2 D-Bus ───────► mpris C++ client
        ├── org.freedesktop.Notifications D-Bus ► notifserver C++ adaptor
        ├── wlr-output-management protocol ────► display C++ client
        └── Hyprland Unix event socket ─────────► Rust IPC daemon
                                                        │
                                    ┌───────────────────┘
                                    ▼
                          C++ QObject singletons & models
                          (own all state, emit Q_PROPERTY signals)
                                    │
                                    ▼
                               QML engine
                          (binds, renders, animates)
```

---

## Design Principles

**No polling where events exist.** If a system API emits signals or events on state change, the shell uses them. Polling is only used where no event mechanism exists (CPU usage from `/proc/stat` being the canonical example), and even then it happens at the C++ level on a single timer — not duplicated across QML `Timer {}` blocks.

**No subprocess parsing for persistent state.** `ShellProcess` and subprocess spawning are reserved for one-shot imperative commands. Anything the shell needs to know continuously — volume, network, Bluetooth, media — is maintained by a long-lived C++ client that talks directly to the appropriate API.

**C++ owns state, QML observes it.** The QML engine never holds authoritative state. If QML and C++ disagree about a value, C++ is correct. This makes the system debuggable — you can inspect C++ state independently of the UI.

**One build system.** The entire C++ layer is one CMake project. There are no compile scripts, no manual `g++` invocations, no implicit dependencies. Adding a new C++ component means adding a target to `CMakeLists.txt`.

**Config is data, not code.** Static configuration — colors, layout options, keybinds, feature flags — lives in a JSON file loaded at runtime. QML components bind to a C++ config singleton that owns this data. Changing config does not require editing QML files.

**The shell is self-contained.** MyBar does not depend on Waybar, eww, mako, dunst, or any other shell component running alongside it. It implements every surface it needs internally. The only external runtime dependencies are Qt6, libpipewire, and the system D-Bus daemon.
