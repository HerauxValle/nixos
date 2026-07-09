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
      for i in $(seq 1 30); do
        if [ -e "/dev/disk/by-label/${usbKeyLabel}" ]; then
          found=1
          break
        fi
        sleep 0.5
      done

      if [ "$found" -eq 0 ]; then
        echo "require-usb-key: ${usbKeyLabel} not detected -- powering off instead of prompting for a passphrase."
        systemctl poweroff
      fi
    '';

  };

}
