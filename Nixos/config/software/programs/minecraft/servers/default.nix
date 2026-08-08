# &desc: "Minecraft server imports -- creative building server + creative testworld."

{ ... }:

{
  imports = [
    ./creative
    ./testworld.nix
  ];
}
