# &desc: "Hardcore server imports -- vanilla-feel Paper, only zero-advantage QoL plugins (Chunky/DiscordSRV/BlueMap), no Multiverse (worlds.nix uses the shared world-creation module's multiverse=false mode instead, for seed + regenerate on its single vanilla-bootstrapped world)."

{ ... }:

{
  imports = [
    ./package.nix
    ./server.nix
    ./plugins.nix
    ./files.nix
    ./ops.nix
    ./ports.nix
    ./worlds.nix
  ];
}
