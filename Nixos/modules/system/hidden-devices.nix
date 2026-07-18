{ config, lib, ... }:

# &desc: "Declares + wires config.vars.hiddenDevices (UUIDs to hide from udisks2), and warns if a reboot is needed."

# One flat file -- this doesn't grow complex enough to earn the
# default.nix/lib split the bigger modules here use. Real values live
# in config/system/hidden-devices.nix, same modules/ vs config/ split
# as everything else.
#
# UDISKS_IGNORE is a real udisks2 mechanism (see its own shipped
# 80-udisks2.rules -- it already hides EFI/RAID/Apple-boot partitions
# this exact way), not a Dolphin-specific hack: hides a device from
# every udisks2-based file manager entirely. Matched by ID_FS_UUID
# (stable per filesystem/LUKS container) rather than device name --
# sda2/loopN/dm-N all get reassigned across boots. Confirmed working
# live after a real reboot: root ("nixos") and all 6 vaults' raw loop
# containers no longer show in Dolphin's Devices panel.
#
# Only takes effect at genuine device-creation time (boot, or a real
# unplug/replug) -- a udevadm trigger/udisks2 restart against an
# already-known device does NOT retroactively hide it, confirmed live.
# Nothing running can fix that from here, so instead of pretending
# otherwise, the activation script below just tells you plainly when a
# reboot is actually needed -- by diffing the new generation's udev
# rules against /run/booted-system (what was actually booted, frozen
# until a real reboot), not /run/current-system (which switch-to-
# configuration updates on every switch, reboot or not -- confirmed
# live this produces a false positive on every single rebuild
# afterward, since it's always comparing a generation against itself).
# Generic to any udev rule change, not specific to this list, and cheap
# (one `diff -rq` over a handful of small rule files, not a full
# system diff) -- and correctly keeps warning on every rebuild until
# you actually reboot, not just once.
{
  options.vars.hiddenDevices = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      ID_FS_UUID values (as `udevadm info` reports them) to hide from
      udisks2 -- and therefore Dolphin/GNOME Files/any Solid-based file
      manager -- entirely. NTFS UUIDs must be uppercase (that's how
      blkid reports them); everything else exactly as udevadm shows it.
    '';
  };

  config = lib.mkIf (config.vars.hiddenDevices != [ ]) {
    services.udev.extraRules = lib.concatMapStringsSep "\n"
      (uuid: ''SUBSYSTEM=="block", ENV{ID_FS_UUID}=="${uuid}", ENV{UDISKS_IGNORE}="1"'')
      config.vars.hiddenDevices;

    system.activationScripts.udevRebootNotice = {
      text = ''
        if ! diff -rq "${config.system.build.etc}/etc/udev/rules.d" /run/booted-system/etc/udev/rules.d >/dev/null 2>&1; then
          echo -e "\033[0;31m[udev] Some settings require a reboot to take effect.\033[0m"
        fi
      '';
    };
  };
}
