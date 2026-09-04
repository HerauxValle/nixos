# &desc: "Enables DDC/CI monitor control (ddcutil) -- schema + wiring live in ../../modules/system/ddc.nix."

{ ... }:

{
  config.vars.system.ddc.enable = true;
}
