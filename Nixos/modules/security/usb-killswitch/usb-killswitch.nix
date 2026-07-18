
{ config, pkgs, lib, ... }:

let
  cfg = config.vars.security.usbKillswitch;

  poweroffCmd =
    if cfg.killMode == "soft" then
      # --no-block: udev RUN workers are short-lived and get reaped by
      # systemd-udevd after a timeout -- this is a fire-and-forget async
      # D-Bus call to PID1, not something that should wait on the worker.
      "${pkgs.systemd}/bin/systemctl --no-block poweroff"
    else if cfg.killMode == "hard" then
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
    else if cfg.killMode == "disabled" then
      null
    else
      throw "usb-killswitch: killMode must be \"soft\", \"hard\", or \"disabled\", got \"${cfg.killMode}\"";

in

# Shutdown-on-removal
lib.mkIf (cfg.killMode != "disabled") {

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
    ACTION=="remove", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_SERIAL_SHORT}=="${cfg.usbSerialShort}", RUN+="${poweroffCmd}"
  '';
}
