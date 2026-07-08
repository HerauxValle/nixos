# MyBar TODO — 2026-06-05 (honest state)

## RULE: No dim/gray overlays. Transparent MouseArea only.

## DONE

## WORKING ON

## C++ Migration Candidates

These four QML components spawn subprocesses or parse text streams where a C++ plugin would be significantly more efficient, reliable, and lower-latency.

### 1. `services/Network.qml` — HIGH PRIORITY
Currently fires ~10 separate `Process` calls (nmcli, bluetoothctl) on timers to get WiFi SSID, signal, IP, MAC, BT device list, etc. Race conditions between calls; no reactivity.

**C++ replacement:** Use **libnm** (NetworkManager GLib API) for WiFi — reactive signals when connection state changes, no polling needed. Use **BlueZ D-Bus via QtDBus** (`org.bluez.Adapter1`, `org.bluez.Device1`) for Bluetooth — object manager gives reactive add/remove/property-changed signals. Expose as a `NetworkBackend` QML singleton with proper Q_PROPERTY bindings.

### 2. `services/NotificationService.qml` — HIGH PRIORITY
Uses a `dbus-monitor` Process to intercept `org.freedesktop.Notifications` calls, then parses the raw text output line-by-line in JS. Fragile (format can change), misses notifications under load, cannot send replies.

**C++ replacement:** Register as a proper `org.freedesktop.Notifications` D-Bus service via **QtDBus** (`QDBusConnection::sessionBus().registerObject`). Implement the full interface (`Notify`, `CloseNotification`, `GetCapabilities`, `GetServerInformation`). Expose notifications as a `QAbstractListModel` to QML. Enables action buttons and notification replies.

### 3. `modules/widgets/CpuWidget.qml` — MEDIUM PRIORITY
Spawns `cat /proc/stat` via `Process` every 2 seconds, parses the output in JS to calculate CPU usage. Subprocess overhead for a trivial file read.

**C++ replacement:** Read `/proc/stat` directly with `QFile` on a `QTimer` (no subprocess). Parse the `cpu` line in C++, emit a `cpuUsageChanged(double)` signal. A `CpuMonitor` QML singleton — ~50 lines of C++.

### 4. `modules/widgets/MemoryWidget.qml` — LOW PRIORITY
Spawns the `free` command every 5 seconds to get memory info. Same subprocess overhead issue.

**C++ replacement:** Read `/proc/meminfo` directly with `QFile`. Parse `MemTotal`, `MemAvailable` lines in C++. A `MemoryMonitor` QML singleton — ~30 lines of C++.

---

**Implementation note:** All four can live in `source/` alongside the existing `appscanner/` C++ binary, built via the same `compile.sh` infrastructure. Network + Notifications give the biggest reliability wins.

## NOT STARTED
