# &desc: "Enables the InputPlumber controller-translation daemon -- schema + wiring live in ../../modules/system/inputplumber.nix."

{ ... }:

{
  config.vars.system.inputplumber.enable = true;
}
