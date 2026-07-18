# &desc: "USB enforcement logic -- if enabled, poweroff at boot if VirtualKeys absent via require-usb-key systemd service."

{ config, pkgs, lib, ... }:

let
  cfg = config.vars.boot.usbRequired;
in

# Power off if USB absent at boot
lib.mkIf cfg.enable {

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
      for i in $(seq 1 ${toString cfg.usbCheckRetries}); do
        if [ -e "/dev/disk/by-label/${cfg.usbKeyLabel}" ]; then
          found=1
          break
        fi
        sleep ${toString cfg.usbCheckDelaySec}
      done

      if [ "$found" -eq 0 ]; then
        echo "require-usb-key: ${cfg.usbKeyLabel} not detected -- powering off instead of prompting for a passphrase."
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
  boot.initrd.systemd.services."systemd-cryptsetup@${cfg.luksDeviceName}" = {
    after = [ "require-usb-key.service" ];
    wants = [ "require-usb-key.service" ];
    overrideStrategy = "asDropin";
  };
}
