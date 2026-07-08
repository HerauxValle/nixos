# MyBar — Implementation TODO

## Priority 1 — Architecture (High Leverage)

### Rust Hyprland IPC Daemon
- [ ] Write a standalone Rust binary using `hyprland-rs` that sits on the Hyprland Unix event socket
- [ ] Emit structured JSON to stdout / a Unix socket that QML reads via `Process`
- [ ] Replace all `ShellProcess { command: "hyprctl ..." }` polling in QML with reactive reads from this daemon
- [ ] Covers: workspace events, window focus, fullscreen state, monitor changes

### C++ State Ownership Inversion
- [ ] Move `ShellState.qml`, `OsdState.qml` logic into C++ `QObject` singletons
- [ ] Register them to the QML engine via `qmlRegisterSingletonInstance`
- [ ] QML binds to `Q_PROPERTY` signals — C++ owns and mutates state, QML only observes
- [ ] Remove the pattern of C++ writing to stdout and QML parsing it for state that should be shared

### Build System
- [ ] Replace `NotificationService/compile.sh` with a proper `CMakeLists.txt`
- [ ] Use `qt_add_qml_module` for QML type registration
- [ ] Integrate all C++ targets (notifserver, appscanner, monitors) into one CMake project
- [ ] Proper dependency tracking — no more manual recompile scripts

---

## Priority 2 — D-Bus Clients (Replace Subprocess Parsing)

### MPRIS — `Mpris.qml`
- [ ] Write a C++ `QObject` D-Bus client for `org.mpris.MediaPlayer2`
- [ ] Expose current player, title, artist, album art URL, playback state as `Q_PROPERTY`
- [ ] Connect to D-Bus property change signals — fully event-driven, zero polling
- [ ] Replace current QML/JS subprocess approach entirely

### BlueZ Bluetooth — `SettingsBluetooth.qml` + `BtDeviceItem.qml`
- [ ] Write a C++ BlueZ D-Bus client (`org.bluez`)
- [ ] Expose device list as `QAbstractListModel` with name, address, connected state, battery
- [ ] Signal on device connect/disconnect/pair events
- [ ] Replace any `bluetoothctl` subprocess parsing in QML

### NetworkManager — `SettingsNetwork.qml` + `NetworkWidget.qml` + `Network.qml`
- [ ] Write a C++ NM D-Bus client (`org.freedesktop.NetworkManager`)
- [ ] Expose active connection, signal strength, IP, type (wifi/eth/vpn) as `Q_PROPERTY`
- [ ] Signal reactively on connection state changes via NM D-Bus signals
- [ ] Replace `nmcli` output parsing in JS entirely
- [ ] Switch `netmonitor.cpp` from `/proc/net/dev` polling to `rtnetlink` netlink socket (event-driven)

### Notifications — `NotificationService/`
- [ ] Ensure `notifserver.cpp` is a proper `org.freedesktop.Notifications` D-Bus service registration
- [ ] If currently launched via shell script glue rather than Qt D-Bus service, rewrite as proper Qt D-Bus adaptor
- [ ] Handle notification actions, hints, urgency levels via D-Bus spec

### PipeWire/PulseAudio Audio — `Audio.qml` + `VolumeWidget.qml` + `VolumePopup.qml`
- [ ] Write a single C++ audio singleton using `libpipewire` (or `libpulse` if PA)
- [ ] Integrate PipeWire event loop with Qt via `QSocketNotifier`
- [ ] Expose volume, mute state, default sink/source, sink list as `Q_PROPERTY` / `QAbstractListModel`
- [ ] Consolidate all three QML audio files into one consumer of this singleton
- [ ] Zero subprocess spawning for audio state

---

## Priority 3 — Wayland Protocol Clients (Replace CLI Tool Calls)

### Display Management — `SettingsDisplay.qml`
- [ ] Implement `wlr-output-management-unstable-v1` Wayland protocol client in C++
- [ ] Expose outputs, modes, refresh rates, scale, transform as models
- [ ] Apply changes directly via protocol — replace `wlr-randr` subprocess calls

### Brightness
- [ ] Implement `wlr-gamma-control-unstable-v1` or use `wlr-output-management` brightness path
- [ ] Alternatively: `logind` D-Bus backlight API for laptop panels
- [ ] Replace `brightnessctl` subprocess calls

### Idle Inhibit
- [ ] Implement `ext-idle-notify-v1` Wayland protocol client in C++ if used
- [ ] Expose inhibit toggle as a proper QML-accessible property

---

## Priority 4 — Refactoring

### `Drawer.qml` (61k chars)
- [ ] Identify logical sections and split into focused sub-components
- [ ] Any list rendering inside → `QAbstractListModel` in C++ if data comes from system
- [ ] Target: no single QML file exceeds ~10k chars

### `WiFiSettings.qml` (34k) + `ControlCenter.qml` (30k)
- [ ] Split into sub-components per logical section
- [ ] Ensure they are pure UI consumers with no subprocess/IPC logic embedded

### `BarConfig.qml` (21k)
- [ ] Move static config data to a `config.json` loaded at runtime
- [ ] Keep only dynamic bindings in QML
- [ ] Allows hot-reload of config without restarting the shell

### `appscanner.cpp` (34k)
- [ ] Split into: `.desktop` parser / icon resolver / category filter as separate translation units
- [ ] Check overlap with Qt's own `.desktop` file handling before reimplementing

### Environment / Config Files
- [ ] Consolidate `variables.env`, `default.env`, `keybind_defaults.env` into one structured config
- [ ] Single source of truth — either JSON consumed by both shell scripts and QML, or a C++ config singleton

### `/proc` Polling in Monitors
- [ ] `cpumonitor.cpp` + `memmonitor.cpp` — audit poll interval; ensure push not double-poll with QML `Timer {}`
- [ ] `netmonitor.cpp` — migrate from `/proc/net/dev` polling to `rtnetlink` netlink event socket
