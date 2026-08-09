# &desc: "Prism Launcher program config -- Minecraft mod/modpack/instance launcher with real Modrinth integration, home-manager only. Launcher config and portable-dir setup each split out."

{ ... }:

{
  imports = [
    ./launcher.nix
    ./portable.nix
  ];
}
