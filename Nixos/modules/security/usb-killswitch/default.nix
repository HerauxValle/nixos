{ lib, ... }:

# Same physical USB stick as boot/luks2 and boot/usb-required -- this file
# owns its own independent copy of these facts (options declared here, not
# shared) so it can be changed or removed without touching the others.
# Logic that reads these lives in ./usb-killswitch.nix, imported below.
# usbSerialShort has no sensible generic default -- its one real
# definition lives in Nixos/config/customized.nix.
{
  imports = [ ./usb-killswitch.nix ];

  options.vars.usbKillswitch = {
    killMode = lib.mkOption {
      type = lib.types.str;
      default = "hard";
      description = ''
        "soft"     -- normal `systemctl poweroff`. Goes through the full ordered
                      shutdown: services stopped, filesystems unmounted, LUKS/
                      dm-crypt mappings torn down cleanly as the last step before
                      power-off. Slower (seconds), but leaves the disk in a clean
                      state on next boot.
        "hard"     -- `systemctl poweroff --force --force`. Bypasses PID1 and the
                      unit-stop sequence entirely: no unmounting, no clean LUKS
                      close. Functionally equivalent to yanking the power cable --
                      the decrypted dm-crypt mapping and any key material in RAM
                      disappear the instant power is gone, same as a clean close
                      would achieve for confidentiality, just without a clean fs
                      unmount (expect a journal replay / fsck on next boot, same
                      as any real unclean power loss -- no worse than that).
        "disabled" -- the udev rule is not installed at all. Pulling the drive
                      does nothing.
      '';
    };

    usbSerialShort = lib.mkOption {
      type = lib.types.str;
      description = ''
        Identifies the physical USB stick whose removal triggers this --
        currently VirtualKeys (the same drive used by boot/luks2.nix and
        security/sudo-keyfile.nix). ID_SERIAL_SHORT, not idVendor/idProduct:
        this drive's USB bridge chip (346d:5678, generic "USB Disk 2.0") is a
        common no-name controller, so vendor/product alone isn't guaranteed
        unique across other sticks with the same chip -- the per-unit serial
        is. Confirmed via `udevadm info --query=all --name=/dev/sdX` against
        this machine's other USB drives (WD-prefixed serials) -- no collision.

        If VirtualKeys is ever replaced/reformatted on different hardware,
        re-check with: udevadm info --query=all --name=/dev/sdX | grep ID_SERIAL_SHORT
      '';
    };
  };
}
