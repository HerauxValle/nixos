# &desc: "appimage program config -- enabled, binfmt_misc handler so *.AppImage runs directly (via appimage-run's FHS wrapper) without typing appimage-run by hand."

{ ... }:

{
  config.vars.packages.programs.appimage.enable = true;
}
