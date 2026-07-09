{ config, pkgs, lib, ... }:

# Variables
let
  # -----------------------------------------------------------------
  # CONFIGURATION
  # "soft"     -- normal `systemctl poweroff`. Goes through the full ordered
  #               shutdown: services stopped, filesystems unmounted, LUKS/
  #               dm-crypt mappings torn down cleanly as the last step before
  #               power-off. Slower (seconds), but leaves the disk in a clean
  #               state on next boot.
  # "hard"     -- `systemctl poweroff --force --force`. Bypasses PID1 and the
  #               unit-stop sequence entirely: no unmounting, no clean LUKS
  #               close. Functionally equivalent to yanking the power cable --
  #               the decrypted dm-crypt mapping and any key material in RAM
  #               disappear the instant power is gone, same as a clean close
  #               would achieve for confidentiality, just without a clean fs
  #               unmount (expect a journal replay / fsck on next boot, same
  #               as any real unclean power loss -- no worse than that).
  # "disabled" -- the udev rule is not installed at all. Pulling the drive
  #               does nothing.
  killMode = "hard";

  # Identifies the physical USB stick whose removal triggers this --
  # currently VirtualKeys (the same drive used by boot/luks2.nix and
  # security/sudo-keyfile.nix). ID_SERIAL_SHORT, not idVendor/idProduct:
  # this drive's USB bridge chip (346d:5678, generic "USB Disk 2.0") is a
  # common no-name controller, so vendor/product alone isn't guaranteed
  # unique across other sticks with the same chip -- the per-unit serial
  # is. Confirmed via `udevadm info --query=all --name=/dev/sdX` against
  # this machine's other USB drives (WD-prefixed serials) -- no collision.
  #
  # If VirtualKeys is ever replaced/reformatted on different hardware,
  # re-check with: udevadm info --query=all --name=/dev/sdX | grep ID_SERIAL_SHORT
  usbSerialShort = "*******************";
  # -----------------------------------------------------------------

  # -----------------------------------------------------------------
  # DO NOT TOUCH
  # -----------------------------------------------------------------

  poweroffCmd =
    if killMode == "soft" then
      # --no-block: udev RUN workers are short-lived and get reaped by
      # systemd-udevd after a timeout -- this is a fire-and-forget async
      # D-Bus call to PID1, not something that should wait on the worker.
      "${pkgs.systemd}/bin/systemctl --no-block poweroff"
    else if killMode == "hard" then
      # Can't just run `systemctl poweroff --force --force` here -- confirmed
      # live: it silently no-ops when launched this way. -ff calls reboot(2)
      # directly in whatever process invokes it, skipping PID1 entirely --
      # but RUN+= commands are forked straight from systemd-udevd itself, so
      # they inherit its own hardened seccomp filter (`systemctl show
      # systemd-udevd -p SystemCallFilter`), which allows sync/syncfs but
      # does NOT include reboot. The child gets killed by seccomp the instant
      # it calls reboot(2); udev doesn't surface that failure at normal log
      # levels, so it fails completely silently.
      #
      # Fix: systemd-run only needs a D-Bus call (allowed by the filter) to
      # ask PID1 -- unsandboxed -- to spawn a fresh transient unit. reboot(2)
      # then happens inside THAT unit, outside udevd's seccomp filter, so it
      # actually goes through. --no-block: don't wait on it from the udev
      # worker, same reasoning as the soft path above.
      "${pkgs.systemd}/bin/systemd-run --no-block --collect --unit=usb-killswitch-hard -- ${pkgs.systemd}/bin/systemctl poweroff --force --force"
    else if killMode == "disabled" then
      null
    else
      throw "usb-killswitch: killMode must be \"soft\", \"hard\", or \"disabled\", got \"${killMode}\"";

in

# Shutdown-on-removal
lib.mkIf (killMode != "disabled") {

  # Fires from systemd-udevd itself (root, restarted by systemd if killed)
  # rather than a userspace watcher process -- nothing here is a PID an
  # unprivileged process (or most malware short of root) can just pkill.
  # This does NOT defend against an attacker with kernel-mode/root access
  # on a live, unlocked system -- they can just disable the rule first.
  # It defends the "walked away / stick got pulled" case.
  #
  # SUBSYSTEM=="block", DEVTYPE=="disk": matches the whole-disk node
  # exactly once per unplug (not once per partition -- sdc1/sdc2/sdc3
  # would each fire their own "remove" otherwise).
  services.udev.extraRules = ''
    ACTION=="remove", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_SERIAL_SHORT}=="${usbSerialShort}", RUN+="${poweroffCmd}"
  '';

}
