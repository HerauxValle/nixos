#!/usr/bin/env python3
# &desc: "Mirrors any real gamepad's already-correct kernel evdev stream 1:1 onto a virtual Xbox360 uinput device -- no report re-parsing, works for any controller (wired or Bluetooth, any brand) since the kernel driver already normalizes transport differences and (for DS4 at least) already speaks the same evdev axis/button codes a real xpad-driven Xbox 360 pad uses."
#
# Why this exists: both sc-controller and InputPlumber re-parse raw
# HID/report data themselves and got DualShock 4 axis/button mapping
# wrong in different ways (see Nixos/modules/system/*.nix git history for
# the full story) -- sc-controller's own Bluetooth device detection never
# even fires for this controller at all, and InputPlumber's generic
# evdev-to-capability translation mixed up trigger and stick axes.
#
# The kernel's own hid_playstation driver, by contrast, already parses
# DS4 HID reports (over USB AND Bluetooth) correctly -- confirmed
# repeatedly by hand this session: ABS_X/Y=left stick, ABS_RX/RY=right
# stick, ABS_Z=L2, ABS_RZ=R2, standard BTN_SOUTH/EAST/NORTH/WEST/TL/TR/
# THUMBL/THUMBR/SELECT/START/MODE for buttons -- the exact same evdev
# codes the kernel's own xpad driver uses for a genuine Xbox 360 pad.
# So instead of another translator with its own parsing bugs, this just
# grabs the real device and replays its already-correct event stream
# onto a virtual device presenting as "Microsoft X-Box 360 pad"
# (045e:028e), which Wine's XInput layer recognizes natively.

import asyncio
import evdev
import pyudev
from evdev import UInput, ecodes as e

XBOX360_CAPS = {
    e.EV_KEY: [
        e.BTN_SOUTH,
        e.BTN_EAST,
        e.BTN_NORTH,
        e.BTN_WEST,
        e.BTN_TL,
        e.BTN_TR,
        e.BTN_SELECT,
        e.BTN_START,
        e.BTN_MODE,
        e.BTN_THUMBL,
        e.BTN_THUMBR,
    ],
    e.EV_ABS: [
        (e.ABS_X, evdev.AbsInfo(0, -32768, 32767, 16, 128, 0)),
        (e.ABS_Y, evdev.AbsInfo(0, -32768, 32767, 16, 128, 0)),
        (e.ABS_RX, evdev.AbsInfo(0, -32768, 32767, 16, 128, 0)),
        (e.ABS_RY, evdev.AbsInfo(0, -32768, 32767, 16, 128, 0)),
        (e.ABS_Z, evdev.AbsInfo(0, 0, 255, 0, 0, 0)),
        (e.ABS_RZ, evdev.AbsInfo(0, 0, 255, 0, 0, 0)),
        (e.ABS_HAT0X, evdev.AbsInfo(0, -1, 1, 0, 0, 0)),
        (e.ABS_HAT0Y, evdev.AbsInfo(0, -1, 1, 0, 0, 0)),
    ],
}

# DS4 (and most pads) expose their gyro/touchpad as separate evdev nodes
# alongside the real gamepad one -- skip those, and skip our own bridged
# output devices so a restart doesn't try to bridge itself.
EXCLUDE_NAME_SUBSTRINGS = ("Touchpad", "Motion Sensors", "Consumer Control", "System Control")
BRIDGE_NAME = "Microsoft X-Box 360 pad"

active: dict[str, asyncio.Task] = {}


def is_candidate(device: "evdev.InputDevice") -> bool:
    if device.name == BRIDGE_NAME:
        return False
    if any(s in device.name for s in EXCLUDE_NAME_SUBSTRINGS):
        return False
    caps = device.capabilities()
    keys = caps.get(e.EV_KEY, [])
    abs_axes = [a for a, _ in caps.get(e.EV_ABS, [])] if e.EV_ABS in caps else []
    return e.BTN_SOUTH in keys and e.ABS_X in abs_axes and e.ABS_Y in abs_axes


async def bridge_device(path: str) -> None:
    try:
        dev = evdev.InputDevice(path)
    except OSError:
        return
    if not is_candidate(dev):
        dev.close()
        return

    print(f"Bridging {dev.name} ({path})", flush=True)
    try:
        dev.grab()
    except OSError as ex:
        print(f"Failed to grab {path}: {ex}", flush=True)
        dev.close()
        return

    ui = UInput(events=XBOX360_CAPS, name=BRIDGE_NAME, vendor=0x045E, product=0x028E, version=0x0110)
    try:
        async for event in dev.async_read_loop():
            if event.type in (e.EV_KEY, e.EV_ABS, e.EV_SYN):
                ui.write_event(event)
    except OSError:
        pass
    finally:
        print(f"Unbridging {dev.name} ({path})", flush=True)
        ui.close()
        try:
            dev.ungrab()
        except OSError:
            pass
        dev.close()
        active.pop(path, None)


async def main() -> None:
    for path in evdev.list_devices():
        active[path] = asyncio.ensure_future(bridge_device(path))

    context = pyudev.Context()
    monitor = pyudev.Monitor.from_netlink(context)
    monitor.filter_by(subsystem="input")

    def handle_udev(action: str, device: "pyudev.Device") -> None:
        devnode = device.device_node
        if not devnode or "/event" not in devnode:
            return
        if action == "add" and devnode not in active:
            active[devnode] = asyncio.ensure_future(bridge_device(devnode))

    observer = pyudev.MonitorObserver(monitor, handle_udev)
    observer.start()

    while True:
        await asyncio.sleep(3600)


if __name__ == "__main__":
    asyncio.run(main())
