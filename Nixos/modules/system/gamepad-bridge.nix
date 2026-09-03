# &desc: "Declares + wires config.vars.system.gamepadBridge (Scripts/GamepadBridge/gamepad_xinput_bridge.py packaged + a system-wide service) -- mirrors any real gamepad's own kernel evdev stream 1:1 onto a virtual Xbox360 device, no third-party translator/report re-parsing involved."

{ config, lib, pkgs, ... }:

# One flat file -- same reasoning as ./openrazer.nix. Real values live in
# config/system/gamepad-bridge.nix, set explicitly (same split as
# packages/programs -- schema + defaults here, personal picks there).
#
# Replaces both sc-controller (USB worked, but its own Bluetooth device
# detection never fires for this DS4 at all -- traced into its DevMon
# code, a real upstream bug, not a config issue) and InputPlumber (detects
# Bluetooth fine, but its generic evdev-to-capability translation mixed up
# trigger and stick axes with no config-level fix found -- capability_map
# only remaps already-classified capabilities, it can't fix a wrong
# initial classification). Both are third-party tools that re-parse raw
# HID/report data themselves and got DualShock 4 wrong in different ways.
#
# The kernel's own hid_playstation driver already parses DS4 correctly,
# over USB *and* Bluetooth alike (confirmed by hand, repeatedly, this
# session) -- and happens to already use the same evdev axis/button codes
# a real Xbox 360 pad's kernel xpad driver uses (ABS_Z/RZ for triggers,
# BTN_SOUTH/EAST/NORTH/WEST/etc. for face buttons). So instead of another
# translator with its own parsing bugs, the bridge script just grabs the
# real device and replays its already-correct event stream 1:1 onto a
# virtual "Microsoft X-Box 360 pad" device, which Wine's XInput layer
# recognizes natively. Generic by design (matches any device exposing
# BTN_SOUTH + ABS_X/Y, not hardcoded to DS4's vendor/product), so any
# controller -- not just this one -- should work the same way, wired or
# Bluetooth, any number simultaneously (each real device gets its own
# independent virtual pad).
{
  options.vars.system.gamepadBridge = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Packages + runs Scripts/GamepadBridge/gamepad_xinput_bridge.py as a system-wide service.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = config.vars.identity.username;
      description = "Unused directly (the service runs as root for /dev/uinput + arbitrary /dev/input/eventX access), kept for parity with other per-user service options and potential future use.";
    };

    restart = lib.mkOption {
      type = lib.types.str;
      default = "on-failure";
      description = "systemd.services.gamepad-bridge Restart policy.";
    };

    restartSec = lib.mkOption {
      type = lib.types.str;
      default = "5";
      description = "systemd.services.gamepad-bridge RestartSec.";
    };
  };

  config = lib.mkIf config.vars.system.gamepadBridge.enable (
    let
      cfg = config.vars.system.gamepadBridge;
      pythonEnv = pkgs.python3.withPackages (ps: [
        ps.evdev
        ps.pyudev
      ]);
      bridgeScript = ../../../Scripts/GamepadBridge/gamepad_xinput_bridge.py;
    in
    {
      systemd.services.gamepad-bridge = {
        description = "Gamepad-to-XInput bridge (any real controller -> virtual Xbox360 device)";
        wantedBy = [ "multi-user.target" ];
        after = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          # Root: needs /dev/uinput write access and the ability to open
          # + EVIOCGRAB arbitrary /dev/input/eventX nodes regardless of
          # which user is logged in (or none at all).
          User = "root";
          ExecStart = "${pythonEnv}/bin/python3 ${bridgeScript}";
          Restart = cfg.restart;
          RestartSec = cfg.restartSec;
        };
      };
    }
  );
}
