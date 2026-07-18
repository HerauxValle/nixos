# &desc: "Schema-only file defining all custom config.vars options -- identity, boot, security, services, packages, system settings."

{ config, lib, ... }:

{
  # =========================================================================
  # CENTRAL VARIABLES -- schema only.
  #
  # Options with a `default =` below are genuinely generic: a value that
  # would make sense to anyone reusing this repo, without knowing anything
  # about you specifically. Options WITHOUT a default are required -- pure
  # personal facts (username, hostname, ...) with no sensible generic
  # value to fake. Their one real definition lives in
  # Nixos/config/config.nix.
  # =========================================================================

  options.vars.identity = {
    username = lib.mkOption {
      type = lib.types.str;
      description = "Primary (and only) user account on this machine.";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/${config.vars.identity.username}";
      description = "Home directory of vars.identity.username -- derived; change username, not this.";
    };

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "networking.hostName. Same literal as username here, but a conceptually distinct fact.";
    };

    networkInterface = lib.mkOption {
      type = lib.types.str;
      description = ''
        Real network interface facing the LAN/router (e.g. "enp3s0") --
        single source of truth for anything that needs it (currently
        modules/system/networking.nix's own interface config and
        modules/system/port-forwarding's DNAT). Previously duplicated as a
        literal string in both places independently.
      '';
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      description = "time.timeZone.";
    };

    stateVersion = lib.mkOption {
      type = lib.types.str;
      description = "Shared system.stateVersion / home.stateVersion.";
    };

    secretsBaseDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos-secrets";
      description = "Root-owned directory holding all generated secrets.";
    };

    gitCommitEmail = lib.mkOption {
      type = lib.types.str;
      description = "Git identity email stamped on the dotfiles-backup snapshot commit.";
    };
  };
}
