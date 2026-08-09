# &desc: "Enables the OpenRazer daemon for the Razer mouse -- schema + wiring live in ../../modules/system/openrazer.nix."

{ ... }:

{
  config.vars.system.openrazer.enable = true;
}
