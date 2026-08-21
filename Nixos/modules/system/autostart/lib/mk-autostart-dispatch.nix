
{ lib, pkgs, id, job }:

# &desc: "Builds the start/stop/restart shell scripts systemd runs for one autostart job."

# One job's ExecStart/ExecStop/ExecReload content. The restart script is
# where "look for execRestart, else stop-then-start, else just start,
# else nothing" actually lives -- ExecReload= is always defined (see
# ../autostart.nix) so `nixos-rebuild switch` (reloadIfChanged) always
# has something correct to call whether or not this job configured its
# own execRestart.
let
  # Same verb as the action currently running -- a "start" dependency
  # gets started first, a "stop" dependency gets stopped first, etc.
  # systemctl on an already-active oneshot+RemainAfterExit unit is a
  # no-op, so this is safe to call unconditionally, every time.
  chase = verb: deps:
    lib.concatMapStringsSep "\n" (dep: ''systemctl ${verb} "autostart@${dep}.service"'') deps;

  sleepFor = ms:
    lib.optionalString (ms > 0) ''
      sleep "$(( ${toString ms} / 1000 )).$(printf '%03d' $(( ${toString ms} % 1000 )))"
    '';

  body = verb: action: ''
    ${chase verb action.dependsOn}
    ${sleepFor action.delay}
    ${action.cmd}
  '';

  restartBody =
    if job.execRestart != null then
      body "restart" job.execRestart
    else if job.execStop != null && job.execStart != null then ''
      ${body "stop" job.execStop}
      ${body "start" job.execStart}
    ''
    else if job.execStart != null then
      body "start" job.execStart
    else
      "";
in
{
  start = pkgs.writeShellScript "autostart-${id}-start" ''
    set -euo pipefail
    ${lib.optionalString (job.execStart != null) (body "start" job.execStart)}
  '';

  stop =
    if job.execStop == null then null
    else pkgs.writeShellScript "autostart-${id}-stop" ''
      set -euo pipefail
      ${body "stop" job.execStop}
    '';

  restart = pkgs.writeShellScript "autostart-${id}-restart" ''
    set -euo pipefail
    ${restartBody}
  '';
}
