# &desc: "Vesktop config imports -- enable toggle plus Vencord settings/plugins/theme."

{ ... }:

{
  imports = [
    ./enable.nix
    ./vencord.nix
  ];
}
