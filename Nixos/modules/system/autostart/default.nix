{ lib, ... }:

# &desc: "Declares config.vars.autostart (global enable + per-job jobs schema), no logic."

# Schema only -- logic lives in ./autostart.nix. A job is always a plain
# root systemd unit (see ./autostart.nix's own header for why) -- there
# is deliberately no per-job "which user does this run as" field, and
# no sudo anywhere: everything here runs as root, at boot, full stop. A
# job needing the real logged-in graphical session (a media-player
# client, say) doesn't belong in this schema at all -- it's its own
# plain systemd.user.services entry elsewhere, not a field bolted onto
# this one.
#
# execStart/execRestart/execStop share one shape (cmd/delay/dependsOn)
# on purpose -- same fields, just a different moment they run at. Only
# execStart is meaningful for a job to do anything; a job with no
# execRestart/execStop simply never gets that action.
let
  action = lib.types.submodule {
    options = {
      cmd = lib.mkOption {
        type = lib.types.str;
        description = "Plain shell command, run as root -- no sudo, no user switch, verbatim.";
      };

      delay = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 0;
        description = "Milliseconds to wait before running cmd.";
      };

      dependsOn = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Sibling job ids that must run this same action first --
          see ./lib/mk-autostart-order.nix for the cycle/unknown-id
          check this is validated against.
        '';
      };
    };
  };
in
{
  imports = [ ./autostart.nix ];

  options.vars.autostart = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Global kill switch -- false disables every job below without touching their own `enabled`.";
    };

    jobs = lib.mkOption {
      default = { };
      description = ''
        Boot-time jobs, keyed by id (e.g. config.vars.autostart.jobs.vaults).
        Each becomes its own systemd.services."autostart@<id>".
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enabled = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "false -- this job is skipped entirely, as if absent.";
          };

          execStart = lib.mkOption {
            type = lib.types.nullOr action;
            default = null;
            description = "Runs on start (boot, or `systemctl start autostart@<id>`). Becomes ExecStart=.";
          };

          execRestart = lib.mkOption {
            type = lib.types.nullOr action;
            default = null;
            description = ''
              Runs on `systemctl reload autostart@<id>`, and is what
              `nixos-rebuild switch` prefers over a plain stop+start
              when this job's own config changed. Becomes ExecReload=.
            '';
          };

          execStop = lib.mkOption {
            type = lib.types.nullOr action;
            default = null;
            description = "Runs on stop, and ahead of execStart when no execRestart is set. Becomes ExecStop=.";
          };
        };
      });
    };
  };
}
