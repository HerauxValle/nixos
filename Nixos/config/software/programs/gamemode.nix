# &desc: "gamemode program config -- enabled, bumps CPU governor/priority while a game runs via `gamemoderun %command%`."

{ ... }:

{
  config.vars.packages.programs.gamemode.enable = true;
}
