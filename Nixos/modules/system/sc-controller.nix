# &desc: "Declares + wires config.vars.system.scController (sc-controller package + its udev rules + a system-wide scc-daemon service) -- translates a real DualShock 4/generic gamepad into a virtual XInput device so games that only read XInput (Elden Ring included) see a controller."

{ config, lib, pkgs, ... }:

# One flat file -- same reasoning as ./openrazer.nix. Real values live in
# config/system/sc-controller.nix, set explicitly (same split as
# packages/programs -- schema + defaults here, personal picks there).
#
# Wine's own joy.cpl confirmed the real gap: a raw DS4 shows up fine
# under DirectInput but never under XInput, and Elden Ring (like on real
# Windows, where DS4Windows exists for exactly this reason) only reads
# XInput. sc-controller ships a dedicated ds4drv.py driver (not generic
# evdev axis guessing) plus proper udev rules, and translates any
# supported controller to a virtual Xbox360 pad by default with no
# per-device config needed -- unlike the hand-rolled InputPlumber
# capability map this replaces, which never got the trigger axes right.
{
  options.vars.system.scController = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "sc-controller package + udev rules + a system-wide scc-daemon service (DS4/generic pad -> virtual XInput translation).";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.sc-controller;
      description = "sc-controller package to use, both for environment.systemPackages and the scc-daemon service's binary.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = config.vars.identity.username;
      description = "systemd.services.scc-daemon User -- needs to run as a real desktop user, not root, for uinput/profile access.";
    };

    daemonFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--alone" "--foreground" ];
      description = "Flags passed to scc-daemon before the 'start' command. --alone skips launching osd-daemon/autoswitch-daemon (no GUI tray needed for plain XInput translation).";
    };

    restart = lib.mkOption {
      type = lib.types.str;
      default = "on-failure";
      description = "systemd.services.scc-daemon Restart policy.";
    };

    restartSec = lib.mkOption {
      type = lib.types.str;
      default = "5";
      description = "systemd.services.scc-daemon RestartSec.";
    };
  };

  config = lib.mkIf config.vars.system.scController.enable (
    let
      cfg = config.vars.system.scController;
    in
    {
      environment.systemPackages = [ cfg.package ];
      services.udev.packages = [ cfg.package ];

      systemd.services.scc-daemon = {
        description = "SC Controller daemon (DS4/generic pad to XInput)";
        wantedBy = [ "multi-user.target" ];
        after = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          ExecStart = "${cfg.package}/bin/scc-daemon " + lib.concatStringsSep " " cfg.daemonFlags + " start";
          Restart = cfg.restart;
          RestartSec = cfg.restartSec;
        };
      };
    }
  );
}
