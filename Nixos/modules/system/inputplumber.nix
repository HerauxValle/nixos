# &desc: "Declares + wires config.vars.system.inputplumber (services.inputplumber daemon + a DualShock4-to-XInput override profile) -- system-wide controller-translation, remaps the PS4 pad into a virtual XInput device so Wine/Bottles/Proton apps see a gamepad without per-game Steam Input."

{ config, lib, ... }:

# One flat file -- same reasoning as ./openrazer.nix. Real value lives in
# config/system/inputplumber.nix.
#
# services.inputplumber.enable (environment.pathsToLink + XDG_DATA_DIRS)
# correctly exposes the package's bundled device profiles -- confirmed via
# RUST_LOG=debug that they load without error, and the bundled
# 60-ps4_gamepad.yaml *does* match our real DualShock 4 correctly. The real
# blocker: InputPlumber's manager only auto-creates a composite device when
# a config's own `options.auto_manage: true` is set, or the daemon-wide
# ManageAllDevices D-Bus property is flipped at runtime -- neither is true
# by default, so "no unused configs found for device" fires for every
# source device even though the matching profile is present and correct.
# None of the bundled *.yaml files set auto_manage except handheld-specific
# ones gated by DMI matches, so a generic USB/BT pad is silently never
# managed unless something opts it in.
#
# Also: the bundled 60-ps4_gamepad.yaml targets "ds5" (a virtual DualSense/
# DirectInput-style device), not XInput, which is what Elden Ring and most
# Wine/Proton games actually look for. Our own override profile sorts
# before it (05- prefix beats 60-), sets options.auto_manage: true so it
# self-activates with no runtime toggle needed, and targets "xb360"
# instead.
{
  options.vars.system.inputplumber.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "services.inputplumber.enable + a self-activating DualShock4 xb360-target override profile.";
  };

  config = lib.mkIf config.vars.system.inputplumber.enable {
    services.inputplumber.enable = true;

    environment.etc."inputplumber/devices.d/05-dualshock4_xinput.yaml".text = ''
      # yaml-language-server: $schema=https://raw.githubusercontent.com/ShadowBlip/InputPlumber/main/rootfs/usr/share/inputplumber/schema/composite_device_v1.json
      version: 1
      kind: CompositeDevice
      name: DualShock 4 (XInput override)
      matches: []
      maximum_sources: 1
      source_devices:
        - group: gamepad
          unique: true
          evdev:
            name: "*Wireless Controller"
            vendor_id: "054c"
            product_id: "{09cc,05c4}"
            handler: event*
      options:
        auto_manage: true
      target_devices:
        - xb360
    '';
  };
}
