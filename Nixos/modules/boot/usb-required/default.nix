# &desc: "USB presence enforcement at boot -- poweroff if VirtualKeys not detected instead of falling through to passphrase prompt; opt-in."

{ lib, ... }:

# Same physical USB stick as boot/luks2 and security/usb-killswitch --
# each of these three owns its own independent copy of these facts
# (options declared here, not shared) so any one can be changed or removed
# without touching the others. Logic that reads these lives in
# ./usb-required.nix, imported below. usbKeyLabel has no sensible generic
# default -- its one real definition lives in Nixos/config/config.nix.
{
  imports = [ ./usb-required.nix ];

  options.vars.boot.usbRequired = {
    # true  -- if the USB key isn't detected during boot, power off instead
    #          of letting cryptsetup fall through to the normal LUKS
    #          passphrase prompt.
    # false -- this file does nothing; boot proceeds exactly as
    #          boot/luks2.nix already handles it on its own (missing
    #          keyfile -> falls through to the passphrase prompt, same as
    #          always).
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Power off at boot if the USB key isn't detected, instead of falling through to a passphrase prompt. Opt-in: a stranger cloning this repo shouldn't inherit a machine that refuses to boot without this exact physical USB stick -- this machine's own real value lives in Nixos/config/config.nix.";
    };

    usbKeyLabel = lib.mkOption {
      type = lib.types.str;
      description = "Filesystem label of the USB stick holding the keyfile.";
    };

    # Same "root" LUKS device name as boot/luks2.nix -- needed here too
    # since this file has to independently force
    # systemd-cryptsetup@root.service to actually wait on this check (see
    # the drop-in below for why).
    luksDeviceName = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Must match hardware-configuration.nix, same as boot/luks2.nix's own copy.";
    };

    # How many times to check for the drive, and how many whole seconds to
    # wait between checks, before giving up and powering off. This USB stick
    # sits behind a USB hub with documented enumeration flakiness on this
    # exact machine (see boot/grub.nix's nohz=off/highres=off comment, and
    # boot/luks2.nix's own 30x0.5s loop for the same device) -- too short a
    # budget risks powering off even though the drive was a beat away from
    # enumerating. Trimmed down from luks2.nix's 15s to 5s since 15s felt too
    # slow in practice; if this starts false-triggering with the drive
    # actually plugged in, raise it back up rather than assuming the feature
    # is broken.
    usbCheckRetries = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "How many times to check for the drive before giving up.";
    };

    usbCheckDelaySec = lib.mkOption {
      type = lib.types.float;
      default = 0.5;
      description = "Whole seconds to wait between each check.";
    };
  };
}
