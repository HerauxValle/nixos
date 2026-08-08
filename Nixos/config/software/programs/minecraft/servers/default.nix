# &desc: "Minecraft server imports -- creative building server. (testworld.nix used to also be imported here -- file's gone from disk as of 2026-08-09, removed the dangling import; recreate it if that was unintentional.)"

{ ... }:

{
  imports = [
    ./creative
  ];
}
