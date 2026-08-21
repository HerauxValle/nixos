# &desc: "Disko config -- exact current disk layout (ESP + LUKS2 btrfs-with-subvolumes root), pinned UUIDs, fully runnable for a real reinstall; NOT imported into nixosConfigurations, purely reference alongside hardware-configuration.nix."

# Reference-only, by design -- this file is not in configuration.nix's
# imports and disko's own NixOS module is not wired into
# nixosConfigurations.herauxvalle in flake.nix. Importing it for real
# would mean deleting hardware-configuration.nix's fileSystems/
# boot.initrd.luks.devices."root" blocks and letting disko generate them
# instead -- a real reboot-risk change on an encrypted root disk that
# hasn't been verified safe yet. Until that verification happens, this
# file only documents the layout (and, unlike a plain reference, is
# genuinely runnable for a real reinstall) so a future reinstall/
# nixos-anywhere can reproduce it exactly. Exposed read-only via the
# `diskoConfigurations.herauxvalle` flake output for schema validation
# (see flake.nix) without ever being run by anything automated.
#
# Scope: only `sda`, the actual NixOS-managed disk. Deliberately excludes
# the data drives at Nixos/config/system/mountpoints.nix (sdb/sdd --
# already declared there, plain unencrypted single-partition btrfs, no
# partitioning complexity disko needs to own), the Ventoy/VirtualKeys USB
# (sdc -- external tooling, not part of this install), and nvme0n1 (the
# separate Windows dual-boot drive, not touched by NixOS at all).
#
# Every value below was read directly off the live system (lsblk/blkid/
# findmnt/hardware-configuration.nix) and cross-checked against disko's
# actual option schema (lib/types/{gpt,luks,btrfs,filesystem}.nix in the
# disko flake input) rather than guessed:
#   - disk: read from $DISKO_TARGET_DEVICE (same pattern as passwordFile
#     below) rather than a literal path -- this file used to hardcode
#     the /dev/disk/by-id path of the physical device currently at
#     /dev/sda (a USB-attached NVMe enclosure), which meant it could
#     only ever target that one exact enclosure. Installation/format.sh
#     is what sets this env var, after asking which disk to target.
#   - ESP: 5G vfat, GPT partition label "ESP" + uuid pinned to the live
#     PARTUUID, mountOptions match hardware-configuration.nix's
#     fileSystems."/boot".options exactly. extraArgs pins mkfs.fat's
#     volume ID (-i) to the live filesystem UUID (692D-01FB, no dash --
#     that's mkfs.fat's own hex-ID format, not a different value).
#   - LUKS partition: GPT label "nixroot" + uuid pinned to the live
#     PARTUUID, mapper name "root" (matches boot.initrd.luks.devices."root"
#     and config.vars.boot.luks2.luksDeviceName's default). device is left
#     at disko's own default (by-partuuid, derived from the uuid pinned
#     above) rather than pinned to the live system's current by-uuid
#     path -- tried pinning it, and it breaks a real format (see its own
#     comment below for why). extraFormatArgs pins --uuid to the live
#     LUKS UUID. initrdUnlock = true so disko contributes
#     boot.initrd.luks.devices."root".device -- modules/boot/luks2/
#     separately contributes keyFile/keyFileSize onto that SAME attrset,
#     and the module system merges the two without conflict since
#     they're different sub-fields (verified by evaluation and by an
#     actual VM install rehearsal, see docs/disko-wiring-verification.md
#     -- the one known, harmless divergence: boot.initrd.luks.devices
#     ."root".device ends up a by-partuuid path after a real reinstall,
#     not the current by-uuid one; same physical partition either way).
#   - passwordFile is read from $DISKO_ROOT_KEYFILE (an environment
#     variable, via builtins.getEnv, hence needing --impure to evaluate)
#     instead of a literal path -- so nothing in this committed file ever
#     points at real key material. At actual install time, export that
#     variable to wherever the VirtualKeys USB's root.key is mounted
#     under the live installer (NOT the running system's own /key, which
#     only exists transiently inside its initrd).
#   - btrfs: LABEL "nixos" + UUID (-U) pinned to the live filesystem UUID,
#     subvolumes @/@home/@log/@nix/@snapshots each with the exact
#     `subvol=` mountOptions hardware-configuration.nix declares (nothing
#     extra -- flags like `ssd`/`space_cache=v2`/`x-initrd.mount` visible
#     in `mount` output are btrfs/NixOS auto-behavior, not declared facts,
#     and reappear on their own from a fresh disko-driven install of this
#     same config). @swap exists on disk but is currently unused
#     (swapDevices = [] in hardware-configuration.nix) -- included with no
#     mountpoint so a reinstall recreates the exact same subvolume set,
#     inert or not.
#
# Pinning every UUID above means a real reinstall onto the SAME physical
# disk reproduces every filesystem/LUKS/GPT-partition UUID exactly, with
# one deliberate exception: the LUKS device path (see its own comment).
# hardware-configuration.nix's fileSystems by-uuid references would all
# still resolve correctly afterward; its boot.initrd.luks.devices."root"
# .device line would need updating to the new by-partuuid path (or, if
# this ever gets wired in for real, disko generates that line itself).
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # Same pattern as passwordFile below -- read from an env var
        # instead of a literal path, so this file isn't tied to one
        # specific physical enclosure. Installation/format.sh is the
        # only thing that's meant to set this.
        device =
          let
            d = builtins.getEnv "DISKO_TARGET_DEVICE";
          in
          if d == "" then
            throw ''
              DISKO_TARGET_DEVICE is unset. Export it to the target
              disk's /dev/disk/by-id/... path before running disko --
              see Installation/format.sh.
            ''
          else
            d;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "5G";
              type = "EF00";
              label = "ESP";
              uuid = "bfee2d78-8b01-4348-bdad-6740817b92e1";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0022"
                  "dmask=0022"
                ];
                extraArgs = [
                  "-i"
                  "692D01FB"
                ];
              };
            };

            luks = {
              size = "100%";
              label = "nixroot";
              uuid = "d7d39674-946f-4d16-aeaf-23d16417a944";
              content = {
                type = "luks";
                name = "root";
                # Deliberately NOT pinned to /dev/disk/by-uuid/80b7960d-...
                # (the live system's current boot.initrd.luks.devices."root"
                # .device value) even though that would look more
                # "byte-identical" on paper -- tried it, and it breaks a
                # real install: that by-uuid path only exists AFTER
                # `cryptsetup luksFormat` writes that UUID into the LUKS
                # header, so formatting a blank partition against it fails
                # outright ("device does not exist"), confirmed live in a
                # VM rehearsal. disko's own default here --
                # /dev/disk/by-partuuid/<the uuid pinned two lines up> --
                # exists immediately after sgdisk creates the partition,
                # which is what formatting actually needs. Functionally
                # identical (same physical partition, both stable
                # identifiers), just not the same string as what's
                # currently in hardware-configuration.nix -- a real
                # reinstall's boot.initrd.luks.devices."root".device would
                # end up as a by-partuuid path instead. Documented, not
                # silently glossed over -- see docs/disko-wiring-verification.md.
                #
                # true -- disko generates boot.initrd.luks.devices."root".device
                # (the by-partuuid path above), and modules/boot/luks2/
                # separately contributes keyFile/keyFileSize onto that SAME
                # attrset (see its own file) -- different sub-fields of one
                # NixOS option, so the module system merges them without
                # conflict. Verified by evaluation, not assumed -- see
                # docs/disko-wiring-verification.md.
                initrdUnlock = true;
                extraFormatArgs = [
                  "--uuid"
                  "80b7960d-fb8d-4dc3-8b01-329770c6e027"
                ];
                passwordFile =
                  let
                    p = builtins.getEnv "DISKO_ROOT_KEYFILE";
                  in
                  if p == "" then
                    throw ''
                      DISKO_ROOT_KEYFILE is unset. Export it to the real
                      keyfile's path (from the VirtualKeys USB, mounted
                      under the live installer) before running disko --
                      never hardcode that path in this file.
                    ''
                  else
                    p;

                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-L"
                    "nixos"
                    "-U"
                    "16dab0c7-d947-4a28-8db7-de8f2c82fb6f"
                  ];

                  subvolumes = {
                    "@" = {
                      mountpoint = "/";
                      mountOptions = [ ]; # disko auto-adds subvol=@
                    };
                    "@home" = {
                      mountpoint = "/home";
                      mountOptions = [ ]; # disko auto-adds subvol=@home
                    };
                    "@log" = {
                      mountpoint = "/var/log";
                      mountOptions = [ ]; # disko auto-adds subvol=@log
                    };
                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [ ]; # disko auto-adds subvol=@nix
                    };
                    "@snapshots" = {
                      mountpoint = "/.snapshots";
                      mountOptions = [ ]; # disko auto-adds subvol=@snapshots
                    };
                    # Exists on the live disk, currently unused
                    # (swapDevices = [] in hardware-configuration.nix) --
                    # no mountpoint, so disko creates the subvolume but
                    # generates no fileSystems/swapDevices entry for it.
                    "@swap" = { };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
