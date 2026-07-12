{ lib, pkgs }:

# Manual-only maintenance actions (sync, cleanup, whatever a service
# needs) as ONE systemd template unit per service instead of a separate
# top-level unit name per action -- `systemctl start
# self-hosted-<name>@<action>` groups under the same unit family as the
# live self-hosted-<name>.service rather than scattering independent
# service names. Never WantedBy=, never a dependency of the live service
# or of system activation -- a rebuild only ever changes what's
# *declared*, never triggers a fetch.
{ name
  # Same default/meaning as mkSelfHostedService's -- an action
  # dispatch unit for a disabled service shouldn't exist either
  # (nothing to act on).
, enabled ? false
, actions # attrsOf str -- action name -> script body
, user
, packages ? [ ]
, environment ? { }
, environmentFile ? null # same as mkSelfHostedService's -- e.g. a model-sync action needing HF_TOKEN
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
lib.mkIf enabled {
  systemd.services."self-hosted-${name}@" = {
    description = "self-hosted: ${name} (%i)";
    path = packages;
    inherit environment;
    serviceConfig = {
      User = user;
      Type = "oneshot";
      ExecStart = "${dispatch} %i";
    } // lib.optionalAttrs (environmentFile != null) {
      EnvironmentFile = "-${environmentFile}";
    };
  };
}
