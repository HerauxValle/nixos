# &desc: "MangoHud enable -- on, but not session-wide; launch per-game via `mangohud %command%` (or stacked with gamemoderun)."

{ ... }:

{
  config.vars.packages.programs.mangohud = {
    enable = true;
    # Off globally so it doesn't attach to every Vulkan/OpenGL app (e.g.
    # the desktop compositor) -- opt in per launch command instead:
    # `mangohud %command%` in Steam, or `mangohud gamemoderun %command%`
    # to get both the perf boost and the overlay together.
    enableSessionWide = false;
  };
}
