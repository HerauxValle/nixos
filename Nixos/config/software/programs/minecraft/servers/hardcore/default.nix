# &desc: "Hardcore server imports -- vanilla Paper, no plugins, no Multiverse (single vanilla-bootstrapped world)."

{ ... }:

{
  imports = [
    ./package.nix
    ./server.nix
    ./files.nix
    ./ops.nix
    ./ports.nix
  ];
}
