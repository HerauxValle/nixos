{ lib, pkgs }:

# Shared builder every per-service module (./ollama, ./comfyui, ...) calls
# for the part that's genuinely identical across all of them: a live
# systemd unit, plus a manual-only reconciliation oneshot for services that
# need one. Each service module owns everything actually specific to it
# (its own typed options, its own package/fetch logic, its own
# reconciliation script content) and calls these with just the handful of
# values that differ. Adding a new service means writing one subfolder
# module against this, not a new engine -- this file is deliberately the
# only place the "how" of running a systemd unit is written.
#
# Plain function library, not a NixOS module itself (no `config`/`options`)
# -- imported directly by each service subfolder: `import ../self-hosted.nix
# { inherit lib pkgs; }`.

rec {

  # The live process. Restart=on-failure replaces the old bash framework's
  # nohup+PID-file+kill-loop entirely.
  mkSelfHostedService =
    { name
    , execStart
    , user
    , packages ? [ ]
    , environment ? { }
    , preStart ? [ ]
    , storage ? [ ]
    , dataDir ? null
    , autoStart ? true
    }:
    {
      systemd.services."self-hosted-${name}" = {
        description = "self-hosted: ${name}";
        # autoStart = false means it still exists and can be started by
        # hand (`systemctl start self-hosted-<name>`), it just isn't
        # pulled in on boot/rebuild.
        wantedBy = lib.optionals autoStart [ "multi-user.target" ];
        path = packages;
        inherit environment;
        serviceConfig = {
          User = user;
          ExecStartPre = lib.imap0
            (i: cmd: "${pkgs.writeShellScript "self-hosted-${name}-prestart-${toString i}" cmd}")
            preStart;
          ExecStart = execStart;
          Restart = "on-failure";
        } // lib.optionalAttrs (dataDir != null) {
          # Some apps (Stash) resolve relative paths against CWD -- give
          # every service a sane default instead of inheriting systemd's
          # own (/). Harmless for ones that only ever use absolute paths.
          WorkingDirectory = dataDir;
        };
      };

      systemd.tmpfiles.rules =
        lib.optionals (storage != [ ])
          (map (s: "L+ ${dataDir}/${s.src} - - - - ${s.dest}") storage);
    };

  # Manual-only maintenance actions (sync, cleanup, whatever a service
  # needs) as ONE systemd template unit per service instead of a separate
  # top-level unit name per action -- `systemctl start
  # self-hosted-<name>@<action>` groups under the same unit family as the
  # live self-hosted-<name>.service rather than scattering independent
  # service names. Never WantedBy=, never a dependency of the live service
  # or of system activation -- a rebuild only ever changes what's
  # *declared*, never triggers a fetch.
  mkActionService =
    { name
    , actions # attrsOf str -- action name -> script body
    , user
    , packages ? [ ]
    , environment ? { }
    }:
    let
      dispatch = pkgs.writeShellScript "self-hosted-${name}-dispatch" ''
        set -euo pipefail
        case "$1" in
        ${lib.concatStrings (lib.mapAttrsToList (action: script: ''
          ${action})
            exec ${pkgs.writeShellScript "self-hosted-${name}-${action}" script}
            ;;
        '') actions)}
          *) echo "self-hosted-${name}: unknown action '$1'" >&2; exit 1 ;;
        esac
      '';
    in
    {
      systemd.services."self-hosted-${name}@" = {
        description = "self-hosted: ${name} (%i)";
        path = packages;
        inherit environment;
        serviceConfig = {
          User = user;
          Type = "oneshot";
          ExecStart = "${dispatch} %i";
        };
      };
    };
}
