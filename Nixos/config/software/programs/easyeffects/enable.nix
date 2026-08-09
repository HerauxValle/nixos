# &desc: "Easyeffects enable -- PipeWire effects GUI (EQ/noise-suppression/etc.), see modules/desktop/desktop.nix for the pipewire/rtkit it needs."

{ ... }:

{
  config.vars.packages.programs.easyeffects.enable = true;
}
