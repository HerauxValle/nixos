# &desc: "Minecraft server imports -- hardcore + creative testworld."

{ ... }:

{
  imports = [
    ./hardcore.nix
    ./testworld.nix
  ];
}
