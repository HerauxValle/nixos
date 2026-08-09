# &desc: "gamemode program config -- enabled, bumps CPU governor/priority + optional GPU perf-level while a game runs via `gamemoderun %command%`."

{ ... }:

{
  config.vars.packages.programs = {
    gamemode.enable = true;

    # /etc/gamemode.ini -- gpu tuning is opt-in per gamemoded(8) ("accept-responsibility"),
    # left conservative here since it can void warranties on some cards.
    gamemodeSettings = {
      general = {
        # Renice gamemoded's target process; needs the cap_sys_nice wrapper,
        # already on by default (programs.gamemode.enableRenice).
        renice = 10;
        # Reduce ioprio (lower priority number = higher priority, 0 is highest).
        ioprio = 0;
        inhibit_screensaver = 1;
      };

      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        # -1 = auto-detect the active GPU.
        gpu_device = -1;
        amd_performance_level = "high";
      };
    };
  };
}
