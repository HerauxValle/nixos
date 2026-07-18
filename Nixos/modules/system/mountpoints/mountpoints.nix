# &desc: "Mount activation script (real bash, not fileSystems) -- live disk queries, LABEL/NAME resolution, blocking exit-code abort."

{ config, lib, pkgs, ... }:

let
  devices = config.vars.system.mountpoints.device;
  globalBlocking = config.vars.system.mountpoints.blocking;

  # Absolute paths throughout, not PATH lookups -- matches
  # modules/backup/dotfiles/dotfiles.nix's own convention (activation
  # scripts run with whatever minimal PATH the activation environment
  # happens to have, not a login shell's).
  lsblk = "${pkgs.util-linux}/bin/lsblk";
  mountBin = "${pkgs.util-linux}/bin/mount";
  mountpointBin = "${pkgs.util-linux}/bin/mountpoint";
  mkdir = "${pkgs.coreutils}/bin/mkdir";
  chown = "${pkgs.coreutils}/bin/chown";

  resolveLeafFn = import ./lib/resolve-leaf.nix { inherit lsblk; };
  mountEntry = import ./lib/mount-entry.nix { inherit lib mountBin mountpointBin mkdir chown globalBlocking; };
in

{
  # Real bash at activation time, not the fileSystems option -- same
  # reasoning as modules/backup/dotfiles/dotfiles.nix's own
  # excludeFiles/redactValues checks: `nixos-rebuild switch` (as pacnix
  # calls it) runs WITHOUT --impure, so builtins.pathExists on a plain
  # string path outside the flake cannot reliably see the real filesystem
  # at eval time (confirmed live -- it reported a disk that was actually
  # mounted as "missing"). Beyond that, `as`'s LABEL/NAME resolution
  # fundamentally needs a live disk query, which fileSystems can't do at
  # all since its mount paths must be known at eval time. Wrapped in a
  # subshell so none of this leaks into the shared global scope every
  # other module's activationScripts.*.text is concatenated into --
  # $mountpointsFailed is local to that subshell too, but its exit code
  # is checked right after and re-thrown into the outer scope, which is
  # what actually makes a blocking entry abort `pacnix rebuild` instead
  # of every module's activationScripts.*.text just running regardless.
  #
  # lib.optionalString, not lib.mkIf -- system.activationScripts.<name>.text
  # is types.lines with no default, so mkIf false would drop the
  # definition entirely instead of contributing "" (same trap documented
  # in modules/services/self-hosted/dotfiles.nix and
  # modules/system/port-forwarding/port-forwarding.nix's own UPnP step).
  # config.vars.system.mountpoints.enabled = false here means genuinely zero
  # activation-script contribution, not even an empty subshell.
  system.activationScripts.mountpoints.text = lib.optionalString config.vars.system.mountpoints.enabled ''
    (
      mountpointsFailed=0
      ${resolveLeafFn}
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList mountEntry devices)}
      [ "$mountpointsFailed" -eq 0 ]
    ) || exit 1
  '';
}
