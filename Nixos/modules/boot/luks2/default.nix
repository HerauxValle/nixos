# &desc: "LUKS2 schema on VirtualKeys USB -- independent copy of USB label/keyfile path, matches hardware-configuration.nix device name."

{ lib, ... }:

# File-owned, intentionally independent of boot/usb-required and
# security/usb-killswitch even though they currently describe the same
# physical USB stick -- see boot/usb-required/default.nix's own comment
# for why. Logic that reads these lives in ./luks2.nix, imported below.
# usbKeyLabel has no sensible generic default (a specific USB stick's
# label) -- its one real definition lives in Nixos/config/config.nix.
{
  imports = [ ./luks2.nix ];

  options.vars.boot.luks2 = {
    # 1. LUKS device name -- must match hardware-configuration.nix's definition.
    #    Used both as the attribute key below and inside the systemd unit name,
    #    since systemd-cryptsetup@<name>.service is generated from it.
    luksDeviceName = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "LUKS device name -- must match hardware-configuration.nix.";
    };

    # 2. Same "root" name as above, referenced via ${cfg.luksDeviceName} in
    #    the systemd unit name (systemd-cryptsetup@root.service). Not a
    #    separate literal anymore -- kept in sync automatically since it's
    #    interpolated.

    # 3. External USB partition's filesystem label holding the keyfile.
    #    Stable external fact -- only change if the USB partition is
    #    reformatted or relabeled.
    usbKeyLabel = lib.mkOption {
      type = lib.types.str;
      description = "Filesystem label of the USB stick holding the keyfile.";
    };

    # 4. Filename of the actual keyfile on that USB partition, as mounted at /key.
    #    Stable external fact -- only change if the keyfile is renamed
    #    or regenerated under a different filename.
    keyFileName = lib.mkOption {
      type = lib.types.str;
      default = "root.key";
      description = "Keyfile's name on the mounted USB stick.";
    };
  };
}
