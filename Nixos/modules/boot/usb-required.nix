{ config, pkgs, lib, ... }:

# Variables
let
  # -----------------------------------------------------------------
  # CONFIGURATION
  # true  -- if VirtualKeys isn't detected during boot, power off instead
  #          of letting cryptsetup fall through to the normal LUKS
  #          passphrase prompt.
  # false -- this file does nothing; boot proceeds exactly as
  #          boot/luks2.nix already handles it on its own (missing
  #          keyfile -> falls through to the passphrase prompt, same as
  #          always).
  enable = false;

  # Same USB stick as boot/luks2.nix and security/usb-killswitch.nix --
  # redeclared here rather than shared, same reasoning as those two files:
  # each module owns its own copy of this fact, so any one of them can be
  # changed or removed independently without touching the others.
  usbKeyLabel = "VirtualKeys";

  # Same "root" LUKS device name as boot/luks2.nix -- needed here too since
  # this file has to independently force systemd-cryptsetup@root.service to
  # actually wait on this check (see the drop-in below for why).
  luksDeviceName = "root";

  # How many times to check for the drive, and how many whole seconds to
  # wait between checks, before giving up and powering off. VirtualKeys
  # sits behind a USB hub with documented enumeration flakiness on this
  # exact machine (see boot/grub.nix's nohz=off/highres=off comment, and
  # boot/luks2.nix's own 30x0.5s loop for the same device) -- too short a
  # budget risks powering off even though the drive was a beat away from
  # enumerating. Trimmed down from luks2.nix's 15s to 5s since 15s felt too
  # slow in practice; if this starts false-triggering with the drive
  # actually plugged in, raise it back up rather than assuming the feature
  # is broken.
  usbCheckRetries = 10;
  usbCheckDelaySec = 0.5;
  # -----------------------------------------------------------------
in

# Power off if USB absent at boot
lib.mkIf enable {

  boot.initrd.systemd.services.require-usb-key = {

    # Same hook point boot/luks2.nix's mount-usb-key uses -- runs before
    # cryptsetup ever gets a chance to prompt for a passphrase, so with
    # this enabled, a missing key never reaches that fallback at all.
    wantedBy = [ "cryptsetup-pre.target" ];
    before = [ "cryptsetup-pre.target" ];
    after = [ "local-fs-pre.target" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";

    # Deliberately not wired to luks2.nix's own mount-usb-key.service --
    # this file has no implicit dependency on that unit's name or
    # internals, only on the same physical USB stick, checked here purely
    # by device presence (not by whether the keyfile mount itself
    # succeeded, which is mount-usb-key's job, not this file's).
    #
    # seq/sleep/systemctl are all already available in the systemd initrd
    # without any extra initrdBin entries (unlike luks2.nix's `mount`,
    # which specifically needed util-linux for the -o ro flag).
    script = ''
      found=0
      for i in $(seq 1 ${toString usbCheckRetries}); do
        if [ -e "/dev/disk/by-label/${usbKeyLabel}" ]; then
          found=1
          break
        fi
        sleep ${toString usbCheckDelaySec}
      done

      if [ "$found" -eq 0 ]; then
        echo "require-usb-key: ${usbKeyLabel} not detected -- powering off instead of prompting for a passphrase."
        systemctl poweroff
      fi
    '';

  };

  # `before`/`wantedBy` against cryptsetup-pre.target alone doesn't make
  # systemd-cryptsetup@root.service actually wait on a specific unit --
  # confirmed live: it prompted for a passphrase without ever waiting on
  # require-usb-key.service, racing straight past it. Same root cause
  # boot/luks2.nix already hit and fixed for mount-usb-key.service:
  # systemd-cryptsetup@root.service is a template instance generated at
  # runtime by systemd-cryptsetup-generator, not a package-provided unit,
  # so overrideStrategy must be forced to asDropin (the default
  # asDropinIfExists can't detect it and would write a full replacement
  # unit instead, breaking boot). This is a second, independent drop-in
  # for the same unit -- NixOS merges the after/wants lists from both
  # this file and luks2.nix's own drop-in together, so neither needs to
  # know about the other's contribution.
  boot.initrd.systemd.services."systemd-cryptsetup@${luksDeviceName}" = {
    after = [ "require-usb-key.service" ];
    wants = [ "require-usb-key.service" ];
    overrideStrategy = "asDropin";
  };

}
