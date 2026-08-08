# &desc: "Creative-only Minecraft server imports -- package/service, serverProperties, plugins, files, worlds, ops, ports each split out. Renamed from the old hardcore.nix (survival/hardcore dropped entirely)."

{ ... }:

{
  imports = [
    ./package.nix
    ./server.nix
    ./plugins.nix
    ./files.nix
    ./worlds.nix
    ./ops.nix
    ./ports.nix
    ./spawn.nix
  ];
}
