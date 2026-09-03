# &desc: "Declares + wires config.vars.system.inputplumber (services.inputplumber daemon + a DualShock4-to-XInput override profile) -- system-wide controller-translation, remaps the PS4 pad into a virtual XInput device so Wine/Bottles/Proton apps see a gamepad without per-game Steam Input."

{ config, lib, pkgs, ... }:

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
#
# Confirmed live (PID inspection of a running Elden Ring bottle) that
# Wine's winebus.sys was opening BOTH our virtual xb360 event node AND the
# raw physical DS4's /dev/hidraw -- our first cut of this profile only
# added the "look like Xbox" source entry and dropped the stock profile's
# `blocked: true` entries that hide the raw hidraw/touchpad/motion nodes
# from every other app. With the real pad still directly visible, Wine
# (and the game) enumerates two gamepads and picks the wrong one for
# on-screen prompts. Re-adding the blocks below (same idea as
# 60-ps4_gamepad.yaml, but hidraw match via idVendor/idProduct which -
# unlike the input-subsystem name/id attrs - do live directly on the
# hidraw sysfs node) so only the translated xb360 device is visible.
#
# Still didn't work after that: `blocked: true` doesn't hide/chmod the raw
# nodes itself -- InputPlumber tries to do that separately via a real
# `setfacl` call to strip the seat's uaccess ACL, and the systemd unit's
# PATH (just coreutils/findutils/grep/sed/systemd) never included the acl
# package, so every hide attempt failed with "Unable to determine setfacl
# command location" (confirmed in the journal) and the raw hidraw/event
# nodes stayed fully world-accessible via logind's uaccess grant -- Wine
# kept opening them directly alongside our virtual xb360 device regardless
# of `blocked: true`. Fix: give the unit's PATH access to setfacl.
{
  options.vars.system.inputplumber.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "services.inputplumber.enable + a self-activating DualShock4 xb360-target override profile.";
  };

  config = lib.mkIf config.vars.system.inputplumber.enable {
    services.inputplumber.enable = true;
    systemd.services.inputplumber.path = [ pkgs.acl ];

    environment.etc."inputplumber/devices.d/05-dualshock4_xinput.yaml".text = ''
      # yaml-language-server: $schema=https://raw.githubusercontent.com/ShadowBlip/InputPlumber/main/rootfs/usr/share/inputplumber/schema/composite_device_v1.json
      version: 1
      kind: CompositeDevice
      name: DualShock 4 (XInput override)
      matches: []
      maximum_sources: 4
      source_devices:
        - group: gamepad
          unique: true
          evdev:
            name: "*Wireless Controller"
            vendor_id: "054c"
            product_id: "{09cc,05c4}"
            handler: event*

        - group: gamepad
          blocked: true
          evdev:
            name: "*Wireless Controller Touchpad"
            vendor_id: "054c"
            product_id: "{09cc,05c4}"
            handler: event*

        - group: gamepad
          blocked: true
          evdev:
            name: "*Wireless Controller Motion Sensors"
            vendor_id: "054c"
            product_id: "{09cc,05c4}"
            handler: event*

        - group: gamepad
          blocked: true
          udev:
            attributes:
              - name: idVendor
                value: "054c"
              - name: idProduct
                value: "{09cc,05c4}"
            subsystem: hidraw
      options:
        auto_manage: true
      target_devices:
        - xb360
    '';
  };
}
