# Mouse/keyboard stutter from USB hub reset-looping

## Summary

Mouse cursor (and keyboard) would intermittently freeze for a fraction of
a second, then continue -- worst right after boot, present only on NixOS
(identical hardware worked fine on Arch Linux and Windows). Root cause:
the kernel's tickless/high-res timer scheduling interacting badly with
this system's USB 3.2 xHCI controller, causing the hub's downstream
full-speed devices to hit protocol errors and get reset by the kernel.
Fixed with two kernel boot parameters -- no hardware changes.

## Environment

- CPU/chipset: Intel Tiger Lake-H, xHCI controller `8086:43ed`
  ("Tiger Lake-H USB 3.2 Gen 2x1 xHCI Host Controller")
- Affected hub: generic "USB2.1 Hub", Realtek RTS5411 chipset
  (`idVendor=0bda, idProduct=5411`)
- Affected devices, both attached via that hub:
  - Razer Viper V2 Pro mouse (`1532:00a5`)
  - Razer Huntsman Mini keyboard (`1532:0257`)
- GPU: RTX 3060 (nvidia proprietary driver, `hardware.nvidia.open = false`)
- Kernel at time of fix: `pkgs.linuxPackages_latest` (7.1.2)
- Confirmed present on kernel 6.18.37, 7.1.2, with both nvidia open and
  proprietary drivers -- not tied to the GPU driver or kernel version.

## Symptoms

- Cursor movement would pause for a fraction of a second, then resume,
  recurring every few seconds during continuous movement.
- Most noticeable moving the cursor over empty desktop / no window
  focused; less apparent (though still present) once windows/programs
  were open and doing their own rendering.
- Worst in the first few minutes after boot.
- Same physical mouse, keyboard, hub, and PC ports as the previous Arch
  Linux install, where this never occurred. Also fine on Windows.

## Root cause

`journalctl -k` showed repeated entries like:

```
usb 1-6.3.3: reset full-speed USB device number 7 using xhci_hcd
usb 1-6.3.4: reset full-speed USB device number 8 using xhci_hcd
```

A live USB protocol capture (`usbmon`, see Diagnostics below) caught the
actual failure before each reset: repeated `-71` (`EPROTO`, protocol
error) on the mouse's interrupt-IN endpoint -- a corrupted/malformed
response from the device, which the kernel recovers from by resetting
the port. This is a documented class of Linux bug affecting full-speed
devices behind a hub, tied to how NO_HZ (tickless) idle and high-resolution
timers schedule CPU wake-ups for servicing time-sensitive USB interrupts --
under certain xHCI controllers, the dynamic timer behavior isn't
consistent enough, causing the controller to miss the split-transaction
window and see it as a protocol error.

Because the same hardware worked on Arch, this was a kernel
scheduling/timer behavior difference, not anything hardware-specific --
confirmed by testing the USB devices directly on the PC's back-panel
ports (bypassing the hub entirely), which reliably eliminated the
resets, isolating the problem to something interacting with this
specific hub in the chain.

## Fix

`Nixos/modules/boot/grub.nix` -- `boot.kernelParams`:

```nix
"nohz=off"
"highres=off"
```

- `nohz=off`: disables tickless idle (`CONFIG_NO_HZ_IDLE`) at boot,
  forcing the kernel back to a fixed periodic timer tick instead of only
  waking on-demand.
- `highres=off`: disables the high-resolution timer subsystem, falling
  back to the older jiffy-based timer.

Both are runtime boot parameters -- no kernel rebuild or different
kernel package required, and reversible by removing the two lines.
Trade-off is marginally less idle power efficiency; no other observed
downside.

## Verification

After rebooting with the fix:

```
journalctl -k -b 0 --no-pager | grep -ci "reset.*usb device"
```

Returned `0` after several minutes of uptime and active mouse use,
versus reliably several-to-dozens of matches per boot before the fix.
Stutter has not recurred since.

Note: grep for `"USB device"` is case-sensitive by default and the
kernel logs it capitalized (`reset full-speed USB device`) -- an earlier
check in this investigation used a lowercase-only pattern and produced a
false "zero resets" reading. Always verify with `-i` or an explicit
case-insensitive flag.

## What was ruled out along the way

In order tried, each with real evidence before moving on, not left
active if it didn't help:

1. **`hardware.nvidia.nvidiaPersistenced = true`** -- GPU was idling at
   its lowest power state (P8) with real utilization spikes and never
   ramping clocks. Persistence mode didn't change this behavior.
2. **`WLR_NO_HARDWARE_CURSORS=1`** (via `~/.config/uwsm/env-hyprland`,
   not Hyprland's own config -- that layer initializes too late for this
   variable) -- confirmed reaching the actual Hyprland process
   (`/proc/<pid>/environ`), stutter unaffected.
3. **`hardware.nvidia.open = false`** (proprietary driver instead of
   open-source kernel module) -- real, measurable improvement: GPU clocks
   started actually ramping under load (traced live, 210MHz → 877MHz)
   where the open module never left 210MHz. Kept this change since it's
   a genuine improvement, but it didn't fix the stutter itself.
4. **Forced max GPU performance** (`NVreg_RegistryDwords` PowerMizer
   override) -- no effect; reverted.
5. **USB autosuspend disabled** on the hub's parent ports
   (`power/control=on`) -- no lasting effect (apparent improvement was
   likely coincidental, given the issue is inherently intermittent).
6. **`usbcore.quirks=<hub>:k`** then **`usbcore.quirks=<mouse>:<kbd>:k`**
   (disable USB Link Power Management, tried at both the hub level and
   the specific device level) -- no effect either way.
7. **CPU governor forced to `performance`** -- no effect.
8. **`pcie_aspm=off`** -- no effect (couldn't even test live; firmware
   doesn't hand ASPM control to the OS at runtime).
9. **Unplugging the USB flash drive** sharing the same hub (used for the
   LUKS keyfile, see `luks2.nix`) -- resets continued on the mouse/
   keyboard regardless, ruling out that drive as the trigger.
10. Investigated USB hub Transaction Translator (TT) bandwidth
    contention between the mouse and keyboard as a theory -- a clean
    single-device test still showed the felt stutter with zero logged
    resets for that device, which showed resets and the felt stutter
    aren't reliably the same signal, and directly led to reconsidering
    timer/scheduling as the actual cause instead of anything USB-specific
    to the devices themselves.

## Diagnostics used

Useful commands for anyone debugging a recurrence or a similar issue:

```
# Watch for USB resets live
journalctl -k -f | grep -i reset

# Count resets so far this boot
journalctl -k -b 0 --no-pager | grep -ci "reset.*usb device"

# Live GPU clock/power state trace
nvidia-smi --query-gpu=pstate,clocks.sm,utilization.gpu --format=csv,noheader,nounits

# USB protocol-level capture (needs root; debugfs usbmon)
sudo modprobe usbmon
sudo timeout 45 cat /sys/kernel/debug/usb/usbmon/1u | tee ~/usbmon_capture.txt
# then grep for non-normal status codes (anything but 0 and -115):
grep -vE " (0|-115):" ~/usbmon_capture.txt | grep -E " -[0-9]+:"
```

## References

- [Devices Connected to a USB Hub Resetting Constantly -- Arch Linux Forums](https://bbs.archlinux.org/viewtopic.php?id=291592)
- [Bug #1803982 "reset full-speed USB device... using xhci_h..." -- Ubuntu](https://bugs.launchpad.net/bugs/1803982)
- Linux kernel USB error codes documentation (`-71 EPROTO`)
