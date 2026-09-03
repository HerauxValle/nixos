# &desc: "Declares + wires config.vars.system.inputplumber (services.inputplumber daemon + a DualShock4-to-XInput override profile) -- system-wide controller-translation, remaps the PS4 pad into a virtual XInput device so Wine/Bottles/Proton apps see a gamepad without per-game Steam Input."

{ config, lib, ... }:

# One flat file -- same reasoning as ./openrazer.nix. Real value lives in
# config/system/inputplumber.nix.
#
# services.inputplumber.enable (environment.pathsToLink + XDG_DATA_DIRS)
# does correctly expose the package's bundled device profiles -- confirmed
# via RUST_LOG=debug that they load without error. But the bundled
# 60-ps4_gamepad.yaml uses a `udev: attributes:` matcher for name/id-vendor/
# id-product, and those sysfs ATTRS live one directory level up from the
# event node itself (on its "device" symlink target, e.g.
# /sys/class/input/event25/device/name) -- InputPlumber's matcher never
# matched our real DualShock 4, confirmed by "No unused configs found for
# device" for every check despite the profile's vendor/product being exact.
# It also targets "ds5" (a virtual DualSense/DirectInput-style device), not
# XInput, which is what Elden Ring and most Wine games actually look for.
#
# Fix: override with our own profile using the same `evdev:` matcher style
# xbox_360_gamepad.yaml itself uses (vendor_id/product_id/handler read off
# already-parsed udev properties, not re-walked sysfs ATTRS -- confirmed
# present on our DeviceAdded event), targeting "xb360" instead of "ds5".
{
  options.vars.system.inputplumber.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "services.inputplumber.enable + a DualShock4 xb360-target override profile.";
  };

  config = lib.mkIf config.vars.system.inputplumber.enable {
    services.inputplumber.enable = true;

    environment.etc."inputplumber/devices.d/61-dualshock4_xinput.yaml".text = ''
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
      target_devices:
        - xb360
    '';
  };
}
