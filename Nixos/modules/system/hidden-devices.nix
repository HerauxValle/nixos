{ ... }:

# &desc: "Hides root, Basic data partition, and vault LUKS containers from udisks2/Dolphin via UDISKS_IGNORE."

# Prototype -- one flat file, not yet split into the usual
# default.nix (schema) + config/ (data) shape everything else here
# follows. Confirmed working after a real reboot: root ("nixos") and
# all 6 vaults' raw loop containers no longer show in Dolphin's Devices
# panel. UDISKS_IGNORE only takes effect at genuine device-creation
# time -- a udevadm trigger/udisks2 restart against an already-known
# device does NOT retroactively hide it, only a real reboot (or an
# actual unplug/replug) does. Next: split into
# config.vars.hiddenDevices + a module generating
# services.udev.extraRules from it, same shape as everything else.
#
# UDISKS_IGNORE hides a device from udisks2's D-Bus API entirely, not
# just Dolphin's automount/prompt behavior -- works for any
# udisks2-based file manager. Matched by ID_FS_UUID (stable per
# filesystem/LUKS container) rather than device name (sda2, loopN,
# dm-N all get reassigned across boots -- confirmed live: one of these
# vaults' own raw container was recorded as "loop0" in an old Dolphin
# state file while actually being loop3 today, same UUID throughout).
{
  services.udev.extraRules = ''
    # root filesystem (decrypted, label "nixos")
    SUBSYSTEM=="block", ENV{ID_FS_UUID}=="16dab0c7-d947-4a28-8db7-de8f2c82fb6f", ENV{UDISKS_IGNORE}="1"
    # root's LUKS container (sda2, locked view)
    SUBSYSTEM=="block", ENV{ID_FS_UUID}=="80b7960d-fb8d-4dc3-8b01-329770c6e027", ENV{UDISKS_IGNORE}="1"
    # Windows "Basic data partition" (nvme0n1p3, unlabeled NTFS) --
    # blkid reports NTFS UUIDs uppercase, unlike the others above
    SUBSYSTEM=="block", ENV{ID_FS_UUID}=="88426A11426A03F2", ENV{UDISKS_IGNORE}="1"
    # Vaults vault -- raw LUKS container (the .img duplicate)
    SUBSYSTEM=="block", ENV{ID_FS_UUID}=="6f57628b-7af9-45f6-bfd4-3b1a32fdd6dd", ENV{UDISKS_IGNORE}="1"
    # Davinci vault -- raw LUKS container
    SUBSYSTEM=="block", ENV{ID_FS_UUID}=="3f6f7485-0ac4-49f1-aafb-5430bc39d21f", ENV{UDISKS_IGNORE}="1"
    # Tor vault -- raw LUKS container
    SUBSYSTEM=="block", ENV{ID_FS_UUID}=="35b91a19-68aa-4856-8538-df295e12ab1d", ENV{UDISKS_IGNORE}="1"
    # SelfHosted vault -- raw LUKS container
    SUBSYSTEM=="block", ENV{ID_FS_UUID}=="28dcfdfb-9e78-41a2-910a-4a132617e7b9", ENV{UDISKS_IGNORE}="1"
    # Modrinth vault -- raw LUKS container
    SUBSYSTEM=="block", ENV{ID_FS_UUID}=="1912efe3-08fc-4ef3-8c36-40b6ea629c1b", ENV{UDISKS_IGNORE}="1"
    # Media vault -- raw LUKS container
    SUBSYSTEM=="block", ENV{ID_FS_UUID}=="e8db5655-bafc-450e-8fb1-bfdc983c3ea5", ENV{UDISKS_IGNORE}="1"
  '';
}
