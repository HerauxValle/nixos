<!-- &desc: "Hyper-detailed chronological writeup of the controller-support saga (2026-09-03, ~13:00-17:35 CEST): every tool tried, every bug found, what was kept vs ripped out, and why the final gamepad_xinput_bridge.py design works. Read this before touching gamepad-bridge.nix, bluetooth.nix, or the bridge script." -->

# Controller Support Saga -- Full Writeup

**Date:** 2026-09-03, roughly 13:00 to 17:57 CEST (~5 hours).
**Goal:** any real gamepad (PlayStation DualShock 4 confirmed, wired or Bluetooth,
any number simultaneously) works as a proper XInput controller in Bottles/Wine,
specifically for Elden Ring, with zero manual steps after boot -- plug in (or
Bluetooth-connect through the normal MyBar panel) and it just works.

**Final state (what's actually deployed right now):**

- `Nixos/modules/system/gamepad-bridge.nix` + `Nixos/config/system/gamepad-bridge.nix`
  -- a small custom Python daemon (`gamepad_xinput_bridge.py`, this same directory)
  that mirrors any real gamepad's kernel evdev stream 1:1 onto a virtual Xbox 360
  uinput device, and hides the physical controller's raw hidraw/touchpad/motion
  nodes from everything else (Wine included) so nothing else can read stale/
  uncalibrated raw data from it.
- `Nixos/modules/system/bluetooth.nix` -- two real kernel/daemon-level fixes kept
  from the investigation: the `hidp` kernel module force-loaded (without it,
  Bluetooth HID profile "connects" at the D-Bus level but the kernel never
  creates an actual input device), and BlueZ's `sixaxis` plugin disabled via
  `bluetoothd --noplugin=sixaxis` (it was auto-registering the wired controller
  for its own BT pairing on every USB enumeration, causing a USB reset each
  time -- a repeating flap loop).
- `Quickshell/MyBar/modules/popups/BluetoothSettings.qml` -- the panel's
  "Connect" button now also (re-)trusts the device and does an explicit HID
  profile connect with a short retry, not just a plain `bluetoothctl connect`.
  BlueZ was silently failing to auto-attach the HID profile to an untrusted (or
  no-longer-trusted) device even after the ACL link connected fine.
- **Removed entirely, on purpose:** InputPlumber and sc-controller, and every
  NixOS module/config file for both. Neither is coming back without a very good
  reason -- see their sections below for exactly why each one is a dead end.

If you're reading this because "the controller stopped working" after some
unrelated change, **start by checking `systemctl status gamepad-bridge.service`
and `systemctl status bluetooth.service`, then re-read the "Known-good
verification checklist" section near the bottom** before changing any code.

---

## 0. The actual constraint that makes this hard

Elden Ring (like most FromSoftware PC ports) **only reads XInput controllers**.
This is true on real Windows too -- it's why DS4Windows exists as a tool at all;
a raw DualShock 4 is not a DS4Windows/Linux-specific problem, it genuinely
isn't recognized by this game without a translator, full stop. Confirmed this
session via Wine's own `joy.cpl` (Control Panel -> Game Controllers): the DS4
shows up perfectly under "Connected (DirectInput devices)", and the "Connected
(XInput devices)" list is permanently empty for it, with BlueZ's own tooltip
text literally saying a device only shows there if it's *not* also present
under DirectInput.

So the requirement was never "make Wine see the controller" (it already does,
trivially, as DirectInput) -- it's "produce a **second**, virtual device that
Wine's XInput layer recognizes, without leaving the raw DirectInput one visible
in a way that confuses the game's own controller-selection logic."

---

## 1. Attempt #1: InputPlumber

InputPlumber (`pkgs.inputplumber`, ShadowBlip's project, the daemon SteamOS/
Bazzite use) is the most obvious tool for this: it's specifically built to
translate arbitrary controllers into virtual target devices including XInput
(`xb360`), with bundled per-device profiles.

### 1.1 -- Getting it to detect the controller at all

- `services.inputplumber.enable = true` alone (environment.pathsToLink +
  XDG_DATA_DIRS) correctly exposes the package's bundled device profiles.
  Confirmed via `RUST_LOG=debug` that they load without error, and the bundled
  `60-ps4_gamepad.yaml` *does* match a real DualShock 4 correctly.
- **Real blocker #1:** InputPlumber's manager only auto-creates a composite
  device when a config's own `options.auto_manage: true` is set, or the
  daemon-wide `ManageAllDevices` D-Bus property is flipped at runtime -- neither
  is true by default. So `"no unused configs found for device"` fires for every
  source device even though a matching profile is present and correct. None of
  the bundled `*.yaml` files set `auto_manage` except handheld-specific ones
  gated by DMI matches (Steam Deck, ROG Ally, etc.), so a generic USB/BT pad is
  silently never managed. **Fix:** wrote a custom `05-dualshock4_xinput.yaml`
  device profile in `/etc/inputplumber/devices.d/` (via `environment.etc`) that
  sets `options.auto_manage: true` explicitly and sorts before the stock `60-`
  profile.
- The bundled `60-ps4_gamepad.yaml` also targets `ds5` (a virtual DualSense/
  DirectInput-style device), not XInput -- the custom profile targeted `xb360`
  instead.

### 1.2 -- Getting Wine to only see the translated device, not the raw one

- Confirmed live (PID inspection of a running Elden Ring bottle) that Wine's
  `winebus.sys` was opening BOTH the virtual `xb360` event node AND the raw
  physical DS4's `/dev/hidraw` at the same time. The first cut of the custom
  profile only added the "look like Xbox" source entry and dropped the stock
  profile's `blocked: true` entries that are meant to hide the raw hidraw/
  touchpad/motion nodes from every other app.
- Re-added the `blocked: true` entries (evdev for touchpad/motion, `udev:
  attributes:` for hidraw). **Still didn't work:** `blocked: true` doesn't
  actually hide/chmod the raw nodes by itself -- InputPlumber tries to do that
  separately via a real `setfacl` call to strip the seat's uaccess ACL, and the
  systemd unit's PATH (just coreutils/findutils/grep/sed/systemd by default)
  never included the `acl` package, so every hide attempt failed with
  `"Unable to determine setfacl command location"` (confirmed in the journal)
  and the raw nodes stayed fully world-accessible via logind's uaccess grant.
  **Fix:** added `systemd.services.inputplumber.path = [ pkgs.acl ];`.

### 1.3 -- The trigger/stick axis bug (never resolved)

L2/R2 were dragging the camera and sticking until another input reset state.
Root cause investigation, in order:

1. Captured raw events on the virtual xb360 device while pressing R2 alone:
   ABS code 3/4 (RightStick X/Y) fired, not a trigger axis. Confirmed
   InputPlumber's *implicit default* evdev->gamepad translation (used when no
   `capability_map_id` is set) mishandles DS4's trigger axes -- same class of
   bug as the bundled `dinput_generic.yaml` capability map, which assumes an
   older ABS_GAS/ABS_BRAKE-for-triggers joystick convention that doesn't match
   `hid_playstation`'s real layout (ABS_Z=L2, ABS_RZ=R2, ABS_RX/RY=right stick).
2. Hand-wrote a `capability_map_id` (`ds4_correct_axes`) nested inside the
   `SourceDevice` entry, with correct evdev axis codes. **Zero effect** --
   confirmed via the composite-device source code that `capability_map` is a
   single, top-level `CompositeDevice` field applied globally, not a per-source
   thing; the nested placement (which the *stock* `60-ps4_gamepad.yaml` also
   uses, for what it's worth -- so the stock profile's button-swap capability
   map silently never applies either, it's just that nobody noticed since the
   swap isn't essential) is simply never read.
3. Moved `capability_map_id` to the composite device's top level (confirmed
   valid there via the JSON schema). **Still zero effect.**
4. Tried switching the primary match to `hidraw:` (vendor_id/product_id)
   instead of `evdev:`, mirroring how the officially-supported
   `60-ps5_ds_gamepad.yaml` (DualSense) matches -- that goes through
   InputPlumber's native, hardcoded-correct HID report parser, no generic
   evdev translation at all. **Failed outright**: `"No driver for hidraw
   interface found. VID: 1356, PID: 2508"` in the journal. InputPlumber's
   native hidraw parser only covers DualSense (`0ce6`), not DualShock 4
   (`09cc`/`05c4`) at all -- a dead end specific to this controller.
5. With `RUST_LOG=debug`, traced the *actual* by-ID capability-map lookup path
   and found the real bug: it only ever checks one **hardcoded relative path**,
   `./rootfs/usr/share/inputplumber/capability_maps`, relative to the daemon's
   *working directory* -- it never falls through to `/etc/inputplumber/
   capability_maps.d` (that dir only feeds a separate, generic bulk-scan-and-
   match code path, unrelated to by-ID lookups declared via
   `capability_map_id`). Worked around this by pointing the systemd unit's
   `WorkingDirectory` at a declarative `/etc/inputplumber/rootfs/usr/share/
   inputplumber/capability_maps/` tree that reproduces the exact relative
   structure the by-ID lookup goes looking for.
6. **This finally got the capability map file to load without error** (no more
   "Unable to read directory" failure right after "Found capability mapping in
   config"). **The axis bug was still 100% present and unchanged** after this.
   At this point the conclusion was: InputPlumber's `capability_map` mechanism
   fundamentally only *remaps already-classified capabilities* (confirmed via
   its own source: `if self.capability_map.is_some() &&
   self.translatable_capabilities.contains(&cap) { self.translate_capability
   (&event).await?; }`) -- it operates *after* the raw evdev event has already
   been assigned a `Capability` (RightStick, LeftTrigger, etc.) by a separate,
   non-overridable built-in translation stage. It cannot fix a *wrong initial
   classification*, only redirect an already-correct one to something else.
   There is no config-level way to fix this for a generic evdev-matched DS4 in
   this InputPlumber version.

### 1.4 -- Multi-controller instability (separate, real, and partially root-caused)

While two DS4 units (one wired, one Bluetooth) were both connected, InputPlumber
repeatedly logged `"Device or resource busy (os error 16)"` for one of them,
and composite devices would silently lose sources. Root cause found late in the
session: **not** an InputPlumber architecture limitation (there's no dedup
logic preventing multiple composite devices, confirmed via source), but a
**stray zombie `inputplumber` process from earlier manual debugging** (started
via `sudo env RUST_LOG=debug ... inputplumber` and never fully killed, since
some `pkill` attempts earlier in the session silently failed due to an
unrelated `sudo` PATH issue) still holding an exclusive `EVIOCGRAB` on the
Bluetooth controller's nodes, causing every legitimate daemon instance's
attempt to grab the same nodes to fail with `EBUSY`. Killing the zombie PID
fixed it immediately, both controllers became independent composite devices.
This was a self-inflicted debugging artifact, not a real InputPlumber bug --
worth remembering because it produced a *lot* of confused troubleshooting
before being found.

### 1.5 -- Verdict: fully removed

Even after root-causing 1.2 through 1.4, the axis bug in 1.3 had no viable
config-level fix, and manual testing later in the session (after switching
away from InputPlumber, but relevant context) showed the tool was also just
generally flaky for this specific controller/BlueZ combination in ways that
were hard to pin down further without patching InputPlumber's own Rust source.
**Every InputPlumber module file was deleted** (`modules/system/inputplumber.nix`,
`config/system/inputplumber.nix`, and their imports) rather than left disabled.

---

## 2. Attempt #2: sc-controller

`pkgs.sc-controller` (kozec's project) is a much older, GUI-oriented tool
originally built for the Steam Controller, with a bundled `ds4drv.py` port for
DualShock 4/5 support specifically.

### 2.1 -- USB path: worked correctly, first try

- `environment.systemPackages`, `services.udev.packages` (for its bundled
  `69-sc-controller.rules`), and a `systemd.services.scc-daemon` running
  `scc-daemon --alone --foreground start` as the real user (needs a desktop-
  adjacent session for uinput/profile access, not root).
- **Real gap found:** `scc-daemon` defaults every newly-seen controller to the
  bundled `"Desktop"` profile (mouse/keyboard emulation), not a gamepad-
  passthrough one -- without setting the profile explicitly it silently never
  feeds any virtual Xbox360 device at all, even though `scc info` correctly
  reports "1 controller detected". Fixed with an `ExecStartPost` retry loop
  calling `scc set-profile "XBox Controller"` (the bundled stock profile) a few
  times until the daemon's control socket is ready.
- With that, the **wired** connection genuinely worked: real virtual Xbox360
  device, correct trigger/stick separation (confirmed via raw event capture:
  ABS code 3/4 changed correctly for a genuine right-stick push, and the
  dedicated `ds4drv.py` USB path parses L2/R2 as real triggers, unlike
  InputPlumber's generic evdev guess).

### 2.2 -- Bluetooth path: a genuine, unfixable-from-config upstream bug

- The DS4 over Bluetooth connects fine at the OS/BlueZ level (confirmed:
  `hcitool con` shows a real authenticated ACL link, and once the `hidp` kernel
  module issue below was found and fixed, a real kernel input device *does*
  get created for it).
- **`scc-daemon` never creates a controller object for it at all.** Root-caused
  by reading `sccdaemon.py`'s `add_controller()` -- there's no dedup/limit
  logic; it unconditionally appends. So the daemon should support N
  simultaneous controllers with auto-incrementing IDs (`ds4`, `ds4:1`, ...,
  confirmed via `ds4drv.py`'s `_generate_id()`). But `scc info` and a direct
  Unix-socket query (`Controller Count: 1`) both confirmed only the USB-based
  controller was ever tracked. Searched the daemon's own log across the whole
  session for any mention of the DS4's vendor/product ID in a Bluetooth
  hotplug context -- **zero hits**. The daemon's own `DevMon` (device monitor)
  bluetooth-hotplug code path simply never fires for this device at all. This
  is a real, reported upstream bug (confirmed via a web search turning up
  multiple long-standing `kozec/sc-controller` GitHub issues, e.g. #358, #393,
  #462, about DS4-over-Bluetooth not being detected) -- not something fixable
  by any NixOS/systemd configuration change.
- Also separately confirmed: while a physical USB DS4 was plugged in, its
  libusb handle stays open (`/dev/bus/usb/001/022` visible in the daemon's own
  `/proc/PID/fd`) *even after the kernel's own `hid_playstation` driver no
  longer shows it in `/proc/bus/input/devices`* -- because `sc-controller`'s
  libusb claim detaches the kernel HID driver from the USB device entirely.
  This made "is the wired controller unplugged" surprisingly hard to verify by
  eye at one point in the session (it looked gone from the normal input device
  list, but was very much still there via `lsusb`/sysfs).

### 2.3 -- Verdict: fully removed

USB-only support isn't the goal (the whole point was wireless), and the
Bluetooth gap is a real upstream bug with no config workaround. **Every
sc-controller module file was deleted** (`modules/system/sc-controller.nix`,
`config/system/sc-controller.nix`, and their imports), same as InputPlumber.

---

## 3. The Bluetooth stack bugs found along the way (kept, unrelated to which
   translator tool is used)

These three were found and fixed *during* the InputPlumber/sc-controller
Bluetooth troubleshooting, but are genuinely independent of which (if any)
translator tool is running -- they're why the DS4 wasn't reliably reachable
over Bluetooth *at all*, regardless of what reads it afterward. All three are
still active in the final setup.

### 3.1 -- `hidp` kernel module never auto-loaded

BlueZ's `sixaxis` plugin messages ("`sixaxis: compatible device connected`")
made it look like the wired controller kept flapping (repeated USB resets in
`dmesg`, correlating with `sixaxis` log lines each time) -- see 3.2 for that.
Separately, and initially confused with the same symptom: connecting the DS4
over Bluetooth would report `Connected: yes` in `bluetoothctl`, the HID profile
would even report `"Connection successful"` when explicitly connected via
`bluetoothctl connect <mac> 00001124-0000-1000-8000-00805f9b34fb` (the
Bluetooth SIG-standard HID profile UUID), and yet **zero kernel input device**
would ever appear. `hcitool con` confirmed a real, authenticated ACL link the
whole time. Checked `lsmod | grep hidp` -- **not loaded**. `sudo modprobe
hidp` and the "Wireless Controller" input nodes appeared within the same
second. Made permanent via `boot.kernelModules = [ "hidp" ];`.

### 3.2 -- BlueZ's `sixaxis` plugin fighting with the wired controller

The wired DS4 kept disconnecting/reconnecting via USB every few minutes all
session (`usb 1-6.3.3: reset full-speed USB device` repeating in `dmesg`),
each one immediately preceded by a `bluetoothd` log line: `"sixaxis:
compatible device connected: Wireless Controller ... setting up new device"`.
BlueZ ships a dedicated plugin for Sony SIXAXIS/DS3/DS4-family controllers that
auto-writes Bluetooth pairing info into any Sony controller it sees connect
over **USB**, so the controller can later be paired over Bluetooth without a
separate pairing dance -- and that write appears to trigger a brief USB reset
on this specific hardware/kernel combination. Since `sc-controller` (and
later, the custom bridge) handle DS4 pairing themselves, this plugin is
redundant and actively harmful here.

**First fix attempt was wrong and shipped broken for a while:**
`hardware.bluetooth.settings.General.DisablePlugins = "sixaxis";` looked
correct (it's a real BlueZ `main.conf` key in general) but **this specific
BlueZ version does not recognize it there** -- confirmed via
`journalctl -u bluetooth.service`: `"Unknown key DisablePlugins for group
General in /etc/bluetooth/main.conf"`. The setting was silently ignored the
entire time it was "active" in config; `sixaxis` was never actually off.
**Real mechanism:** `bluetoothd`'s own `-P`/`--noplugin=<name>` command-line
flag (`bluetoothd --help`, `man bluetoothd`), which has to go on `ExecStart`
via a systemd override:

```nix
systemd.services.bluetooth.serviceConfig.ExecStart = [
  ""
  "${config.hardware.bluetooth.package}/libexec/bluetooth/bluetoothd -f /etc/bluetooth/main.conf --noplugin=sixaxis"
];
```

Confirmed fixed: after switching to this and restarting `bluetooth.service`,
the `"Unknown key"` warning disappeared and no more `sixaxis`/USB-reset lines
appeared in the log for the rest of the session.

### 3.3 -- BlueZ won't auto-attach HID to an untrusted (or no-longer-trusted) device

Even with 3.1 and 3.2 fixed, connecting through MyBar's Bluetooth panel
("Connect" on an already-paired device) would show `Connected: yes` in the UI
but produce zero input device -- `journalctl -u bluetooth.service` showed
`profiles/input/device.c:control_connect_cb() connect to <mac>: Host is down
(112)`. Checked `bluetoothctl info <mac>` -- `Trusted: no`. BlueZ's input
profile auto-connect silently refuses to attach to a device that isn't
trusted, and trust can get reset by some disconnect/re-pair cycles (observed
directly this session). Manually running `bluetoothctl trust <mac>` before
connecting fixed it immediately and repeatably.

**Where this actually got fixed:** not in a NixOS module -- in
`Quickshell/MyBar/modules/popups/BluetoothSettings.qml` directly, since the
requirement was "must work through the normal MyBar panel, no CLI ever needed
by the user again". The panel's `btConnectProc` (the "Connect" button on an
already-paired device) now runs `bluetoothctl trust <mac> && bluetoothctl
connect <mac>`, then does an explicit HID-profile connect as a *separate*
follow-up step with a short retry (a plain `connect`'s *implicit* HID-profile
attach kept failing outright with the same "Host is down" error even once
trusted -- the profile has to be connected explicitly). The retry is scoped to
only run for devices that actually advertise the HID profile UUID (checked via
`bluetoothctl info <mac> | grep -qi <uuid>` first), so it adds zero delay for
non-gamepad Bluetooth devices (headphones, etc.) -- those just connect exactly
as before. The `btPairProc` ("Pair" on a brand-new device) got the same
explicit-HID-retry step appended for the same reason.

---

## 4. Attempt #3 (final, working): a custom bridge script

By this point in the session, the actual technical picture was:

- The **kernel's own `hid_playstation` driver already parses DS4 HID reports
  correctly**, over USB *and* Bluetooth alike -- confirmed repeatedly by hand,
  via raw `evdev.capabilities()` dumps: `ABS_X/Y`=left stick, `ABS_RX/RY`=right
  stick, `ABS_Z`=L2, `ABS_RZ`=R2, standard `BTN_SOUTH/EAST/NORTH/WEST/TL/TR/
  THUMBL/THUMBR/SELECT/START/MODE` for buttons -- the *exact same* evdev codes
  the kernel's own `xpad` driver uses for a genuine Xbox 360 pad.
- Both third-party translators re-parse raw HID/report data themselves (DS4
  driver code in each case) and got it wrong in different, tool-specific ways:
  InputPlumber's generic axis classification is not overridable via config,
  and sc-controller's Bluetooth hotplug path has a real, long-standing,
  reported upstream bug that never fires at all.

So instead of a third translator with its own potential parsing bugs, the
final approach is a **small, purpose-written script** that does the minimum
possible: open the kernel's already-correct evdev device, and mirror its event
stream 1:1 onto a virtual uinput device that presents as a genuine Xbox 360
pad (vendor `0x045e`, product `0x028e`). No HID report parsing at all --
purely relaying evdev events the kernel has already decoded correctly.

Deployed as `Scripts/GamepadBridge/gamepad_xinput_bridge.py`, packaged and run
via `Nixos/modules/system/gamepad-bridge.nix` (schema/defaults) +
`Nixos/config/system/gamepad-bridge.nix` (explicit personal values, same
schema/config split convention as the rest of this repo). Generic by design --
matches any device exposing `BTN_SOUTH` + `ABS_X`/`ABS_Y`, not hardcoded to
DS4's vendor/product, so in principle any controller works the same way.

### 4.1 -- Bug: `RuntimeError: no current event loop` on hotplug (new controllers after startup)

`pyudev.MonitorObserver` runs its callback in its **own thread**, not the
asyncio event loop's thread. The first version called `asyncio.ensure_future()`
directly inside that callback, which works fine for the *initial* synchronous
scan at startup (that code runs in the main thread, which does have a running
loop) but throws `RuntimeError: There is no current event loop in thread
'Thread-1'` for every device that connects *after* the daemon has already
started -- confirmed live in the very first test run (both controllers were
already connected at boot, so the initial scan succeeded and masked the bug
completely; it only surfaced once something connected fresh). Fixed by
capturing the running loop once in `main()` and using
`asyncio.run_coroutine_threadsafe(bridge_device(devnode), loop)` from the
udev callback instead of `asyncio.ensure_future()`.

### 4.2 -- Bug: `python-evdev`'s per-axis `AbsInfo` silently not applied

Declared each axis with its own `evdev.AbsInfo(...)` in the `UInput(events=...)`
constructor call (e.g. triggers as `0..255`, sticks as `-32768..32767`).
Confirmed via direct `EVIOCGABS` ioctl reads on the resulting device that
**every single axis ended up with the same declared range regardless of what
was actually requested per-code** -- reproduced in isolation with a minimal
standalone test script, so it's a real quirk of this `python-evdev` version's
`UInput._prepare_events()`/`_uinput.setup()` path, not a mistake in how the
capabilities dict was structured (the flattening logic in
`_prepare_events()` was read line-by-line and looks structurally correct for
the input given).

Rather than keep fighting an undocumented library behavior, the fix sidesteps
it entirely: **read back the actual live range the output device ended up
with** (via `ui.device.absinfo(code)`, ioctl-backed, so it reflects reality
regardless of *why* it ended up that way) and the **actual live range the
source device reports** (`dev.absinfo(code)`, also ioctl-backed -- and this is
where it was separately discovered that DS4 reports *all* axes, sticks
included, on a `0..255` range, not the `-32768..32767` a genuine `xpad`-driven
pad uses -- the earlier assumption that only triggers needed rescaling was
itself wrong). Every `EV_ABS` event gets rescaled from the source's real range
to the destination's real range at forward-time, generically, per axis code --
no hardcoded assumption about what either range "should" be.

### 4.3 -- Bug: undeclared `BTN_TL2`/`BTN_TR2` (and touchpad-click) events silently killing the bridge task mid-session

**Symptom as originally reported:** L2, R2, and the touchpad's click button
each independently made the camera rotate continuously in one direction, and
it never stopped even after releasing the button -- confirmed present for
both wired and wireless.

**First (wrong) theory:** DS4's main gamepad evdev node sends `BTN_TL2`
(312) / `BTN_TR2` (313) as *digital* trigger-press buttons, in addition to the
analog `ABS_Z`/`ABS_RZ` axis, for the exact same physical L2/R2 press (XInput
has no such digital trigger button concept at all). These codes were never
declared in `XBOX360_CAPS`, and forwarding an undeclared code to a uinput
device raises on write. The theory was that this exception propagated out of
the whole `async_read_loop`, silently killing that controller's bridge task
mid-session, after which the stick/trigger axes would stay frozen at whatever
raw value they held at the exact moment of the crash forever (nothing left
alive to ever re-center them) -- which *looks* exactly like "the camera keeps
rotating on its own", since a frozen non-center right-stick value reads to the
game as a constant, continuous turn input.

Implemented a fix for this (filter `EV_KEY` events to only forward codes
actually present in `XBOX360_CAPS`, and wrap every single per-event write in
its own `try/except` so one bad event can never kill the whole loop again) and
shipped it. **The user re-tested and reported the symptom completely
unchanged, still on both wired and wireless, still for L2/R2/touchpad.**
Checked the bridge's own systemd journal across the entire test session
afterward: **zero "Unbridging" or "Dropped event" log lines at all** -- the
bridge task never crashed or restarted once during the whole test. So the
crash theory, while a real and legitimate bug worth fixing on its own
merits (undeclared-key forwarding genuinely can raise, and now can't kill the
loop), was **not the actual cause of the reported symptom**. Per explicit
instruction, this fix was reverted back to the pre-4.3 version (the last
confirmed-working checkpoint) before continuing to investigate, rather than
layering more unverified changes on top.

### 4.4 -- The real cause: Wine reading the raw physical controller directly, in parallel with the bridge

**Key clue that broke the case open:** the user explicitly clarified the
touchpad *click* also caused the exact same continuous-rotation symptom -- and
the bridge script **never touches the touchpad device at all** (it's
explicitly excluded by name, `"Touchpad" in EXCLUDE_NAME_SUBSTRINGS`, and
never opened). If a device the bridge never reads from can still cause the
bug, the bug cannot be inside the bridge's own event-forwarding logic at all.

Verified directly, live, with Elden Ring actually running and the camera
actively drifting at the time of the check (not a guess, not a static
snapshot): read `/proc/<winedevice.exe pid>/fd/*` for both `winedevice.exe`
processes. Confirmed Wine had **all four** of these open simultaneously:

- `/dev/input/event28`, `/dev/input/event256` -- the two clean bridged virtual
  Xbox 360 devices (correct, expected).
- `/dev/hidraw13`, `/dev/hidraw14` -- the two physical controllers' **raw**
  hidraw nodes (wrong -- these were never hidden from anything).

Grabbing (`EVIOCGRAB`) the main gamepad evdev node only stops *that specific
device node's* events from reaching other listeners -- it does nothing at all
about the completely separate `/dev/hidraw*` character device for the same
physical controller, or the touchpad/motion evdev sub-nodes, all three of
which stayed fully world-readable (or at least user-readable) the entire
session. Wine's own DirectInput/`winebus.sys` layer was reading uncalibrated
raw HID report data straight from these, in parallel with the clean XInput
device from the bridge, and something in that mix (very plausibly Elden
Ring's own controller-input blending/last-active-device logic, though this
wasn't traced further once the actual data leak was found and closed) was
what produced the continuous camera drift.

**Fix, implemented in `hide_sibling_raw_devices()`:** after successfully
grabbing the main gamepad evdev node, walk up its udev device tree to the
physical controller's `"hid"`-subsystem parent (the common ancestor of the
gamepad, touchpad, and motion-sensor evdev nodes *and* the raw hidraw device,
however many tree levels apart each one is from the others), then find every
sibling device (any depth, matched via a `sys_path` string-prefix check rather
than `pyudev`'s `list_devices(parent=...)`, which -- confirmed live -- only
returns *direct* children and silently misses the touchpad/motion nodes,
which sit one level deeper) and lock each one down.

Two separate mechanisms were needed, confirmed live, one at a time:

1. `setfacl -b <node>` -- strips the seat's `uaccess` ACL grant. This alone
   was enough for `/dev/hidraw13`/`/dev/hidraw14` (confirmed via `getfacl`
   before/after: the `user:herauxvalle:rw-` entry disappeared, and the base
   permission bits were already `crw-rw----` with no world access, so removing
   just the ACL grant was sufficient).
2. `chmod o-rw <node>` -- **also required** for the touchpad/motion evdev
   nodes specifically. Confirmed via `ls -la` that these had **world-readable
   base permission bits** (`crw-rw-rw-`), unlike the hidraw nodes -- so
   stripping ACL entries alone changed nothing, since the base "other" bits
   already granted access regardless of any ACL. Both `setfacl -b` and
   `chmod o-rw` are now run on every sibling node, unconditionally, to cover
   either case without needing to know in advance which permission model a
   given node happens to use.

Needed `pkgs.acl` (for `setfacl`) and `pkgs.coreutils` (for `chmod`) added to
the systemd service's `path`.

**Confirmed fixed** via direct `ls -la`/`getfacl` checks on all four sibling
nodes after the fix, matching what the earlier live-running-game inspection
showed was open (i.e., the fix targets exactly the four nodes that were
observed to be the problem, not a broader guess).

### 4.5 -- Bug: fast disconnect+reconnect sometimes never noticed (reconnect race)

**Symptom:** unplugged the wired controller, paired the wireless one fresh
through MyBar's panel (showed "Connected" in the UI, red status dot), but the
controller didn't work in-game. Checked the bridge's journal: the *last* line
was `"Unbridging Wireless Controller"` -- no new `"Bridging"` line ever
followed, even though a real kernel input device existed for the fresh
reconnection (confirmed via `/proc/bus/input/devices`).

Root cause: the original hotplug handler only listened for udev `"add"`
actions, and relied purely on `bridge_device()`'s own `async_read_loop()`
eventually hitting an `OSError` (when the old device disappears) to trigger
its `finally` block's `active.pop(path, None)` cleanup. That's a real race: if
a device disconnects and a *new* connection reusing the same event-node path
arrives before the OS has surfaced a read failure on the old (now-dead) file
descriptor, the udev `"add"` handler sees `devnode in active` (pointing at the
stale, not-yet-cleaned-up old task) and skips bridging the new connection
entirely -- the bridge silently gets stuck thinking a dead connection is still
the live one.

**First fix attempt, rejected:** a periodic 2-second rescan loop (re-run
`evdev.list_devices()` + bridge anything not currently tracked, as a
polling-based safety net). Explicitly rejected per instruction -- "loops are
not instant and cause performance drops". Correct call: it papered over the
race with polling latency instead of actually fixing the ordering problem, and
adds needless recurring work for a case that should just be event-driven.

**Real fix:** handle udev `"remove"` actions explicitly, and actively cancel
the corresponding task the moment `"remove"` fires (`loop.call_soon_threadsafe
(task.cancel)`, since the udev callback runs in `pyudev.MonitorObserver`'s own
thread, not the asyncio loop's) instead of waiting for the read loop to
eventually notice on its own. Python guarantees `bridge_device()`'s `finally`
block runs on cancellation same as on a normal exception, so `active.pop()`
happens synchronously with the `"remove"` event -- by the time the *following*
`"add"` event for the new connection arrives, the dict entry is already gone,
no race window at all. `needs_bridging()` (used by both the `"add"` handler
and the startup scan) now also treats a `.done()` task as available, not just
a missing dict key, in case some other code path leaves a finished task
sitting in `active`.

---

## 5. Known-good verification checklist

Run these in order if a controller "stops working" after any future change.
None of them require the game to be running.

```bash
# 1. Both services healthy?
systemctl status gamepad-bridge.service
systemctl status bluetooth.service

# 2. hidp actually loaded? (boot.kernelModules should have made this permanent)
lsmod | grep hidp

# 3. sixaxis actually disabled? (should show --noplugin=sixaxis, no "Unknown key" warning anywhere in the journal)
systemctl cat bluetooth.service | grep ExecStart
journalctl -u bluetooth.service --no-pager | grep -i "unknown key"   # should be empty

# 4. Virtual Xbox 360 device(s) present, one per connected physical controller?
grep -A6 "X-Box" /proc/bus/input/devices

# 5. Bridge log: both controllers bridged, no "Unbridging"/crash lines since the last connect?
journalctl -u gamepad-bridge.service --no-pager -n 30

# 6. Raw sibling devices actually hidden? (no world access, no ACL grant to your user)
#    Find the real controller's hidraw/event numbers via /proc/bus/input/devices first.
ls -la /dev/hidrawN /dev/input/eventN
getfacl /dev/hidrawN /dev/input/eventN

# 7. If you changed the bridge script or restarted the service: the game/Bottles
#    MUST be relaunched fresh afterward. A rebuild/restart tears down the old
#    virtual devices and creates new ones with different event/js numbers --
#    any already-running Wine session keeps holding the dead ones and will
#    silently stop working, with everything above still reporting "healthy".
ps aux | grep -iE "eldenring.exe|winedevice" | grep -v grep
```

---

## 6. Files touched, final state

```
Nixos/modules/system/gamepad-bridge.nix   -- schema + service definition
Nixos/config/system/gamepad-bridge.nix    -- explicit enable + values
Nixos/modules/system/bluetooth.nix        -- hidp module, sixaxis --noplugin
Scripts/GamepadBridge/gamepad_xinput_bridge.py  -- the actual bridge (this dir)
Scripts/GamepadBridge/JOURNEY.md          -- this file
Quickshell/MyBar/modules/popups/BluetoothSettings.qml  -- trust + HID retry on Connect/Pair
```

Deleted entirely (not disabled, not commented out -- gone):

```
Nixos/modules/system/inputplumber.nix
Nixos/config/system/inputplumber.nix
Nixos/modules/system/sc-controller.nix
Nixos/config/system/sc-controller.nix
```
