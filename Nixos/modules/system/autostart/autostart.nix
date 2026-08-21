
{ config, lib, pkgs, ... }:

# &desc: "Turns config.vars.system.autostart.jobs into one independent root systemd unit per job."

# Every job gets its OWN concrete systemd.services."autostart@<id>" --
# deliberately not one real systemd template (a single shared
# autostart@.service file instantiated by %i). A real template means
# `nixos-rebuild switch` can only diff ONE file, so changing any single
# job's cmd would reload every currently-running job, not just the one
# that changed. Separate concrete units (named with a literal "@" purely
# for the same family-grouping look as self-hosted's mkActionService,
# not because systemd treats them as instances of a shared template)
# fix that: only the job that actually changed ever gets touched.
#
# Not a --user unit and no sudo anywhere -- every job runs as root by
# systemd's own default, automatically, on boot. `systemctl restart
# autostart` restarts every job (PartOf=autostart.target cascades it);
# `systemctl restart autostart@<id>` restarts just one. No teardown
# script needed either: flipping config.vars.system.autostart.enabled to false
# means no units are declared in the next generation, and NixOS's own
# switch-to-configuration already stops/removes units that vanished
# between generations.
#
# `path = [ config.system.path ]` on every job -- a plain systemd
# service's default PATH is a small, fixed, build-time set (coreutils/
# findutils/gnugrep/gnused/systemd), NOT /run/current-system/sw/bin.
# Confirmed live: a job whose cmd invoked a `#!/usr/bin/env python3`
# script failed with "env: 'python3': No such file or directory" before
# this was added -- `cmd` is meant to be an arbitrary command exactly
# like the old manifest's, so it needs the same PATH an interactive
# login shell would resolve against (everything in
# environment.systemPackages), not a hand-picked allowlist per job.
let
  cfg = config.vars.system.autostart;
  enabledJobs = lib.filterAttrs (_: job: job.enabled) cfg.jobs;
  order = import ./lib/mk-autostart-order.nix { inherit lib; } { jobs = enabledJobs; };

  mkJob = id: job:
    let
      scripts = import ./lib/mk-autostart-dispatch.nix {
        inherit lib pkgs id job;
      };
    in
    lib.nameValuePair "autostart@${id}" {
      description = "autostart: ${id}";
      wantedBy = [ "multi-user.target" "autostart.target" ];
      partOf = [ "autostart.target" ];
      reloadIfChanged = true;
      path = [ config.system.path ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = scripts.start;
        ExecReload = scripts.restart;
      } // lib.optionalAttrs (scripts.stop != null) {
        ExecStop = scripts.stop;
      };
    };
in
lib.mkIf cfg.enabled {
  assertions = order.assertions;

  systemd.targets.autostart.description = "All autostart jobs";
  systemd.services = lib.listToAttrs (lib.mapAttrsToList mkJob enabledJobs);
}
