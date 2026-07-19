# &desc: "silentSDDM program config -- enabled with login/lock wallpaper sourced from Scripts/Wallpaper."

{ ... }:

{
  config.vars.packages.programs.silentSDDM = {
    enable = false;
    wallpaper = ../../../../Scripts/Wallpaper/wallpaper.jpg;
  };
}
