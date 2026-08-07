# &desc: "Minecraft config imports -- settings.nix (eula/dataDir) plus servers/, sets nixpkgs services.minecraft-servers directly, no custom schema."

{ ... }:

{
  imports = [
    ./settings.nix
    ./servers
  ];
}
