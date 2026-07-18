{ ... }:

# &desc: "One real example config.vars.autostart.jobs entry for reference."

# =========================================================================
# EXAMPLES -- config.vars.autostart, commented out. Same shape as
# glossar/main/variables.nix, scoped to one module. Schema:
# modules/system/autostart/default.nix. Real values on this machine:
# config/system/autostart.nix. Full design reference:
# modules/system/autostart/docs/architecture.md.
#
# Every job runs as root, at boot, with no sudo -- see
# docs/architecture.md for why there's no per-job "user" field. A job
# needing your actual logged-in session isn't part of this schema; it's
# its own separate systemd.user.services entry elsewhere.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste
# reference. Copy a block into config/system/autostart.nix and uncomment
# it there to actually set it.
# =========================================================================

{
  # config.vars.autostart = {
  #   enabled = true; # global kill switch -- false disables every job below

  #   jobs = {
  #     example = {
  #       enabled = true; # optional -- false skips this one job, as if absent

  #       execStart = {
  #         cmd = "echo hello";
  #         delay = 0;          # optional -- milliseconds to wait before cmd
  #         dependsOn = [ ];    # optional -- sibling job ids to run this same action on first
  #       };

  #       # optional -- omit entirely for a job with no lighter-weight
  #       # reload path; `nixos-rebuild switch` then falls back to
  #       # execStop-then-execStart (or just execStart, if no execStop).
  #       execRestart = {
  #         cmd = "echo restarting";
  #         delay = 0;
  #         dependsOn = [ ];
  #       };

  #       # optional -- omit entirely for a job with nothing meaningful
  #       # to do on stop.
  #       execStop = {
  #         cmd = "echo bye";
  #         delay = 0;
  #         dependsOn = [ ];
  #       };
  #     };

  #     # a second job that waits for "example" above before starting
  #     dependent = {
  #       execStart = {
  #         cmd = "echo after example";
  #         dependsOn = [ "example" ];
  #       };
  #     };
  #   };
  # };
}
