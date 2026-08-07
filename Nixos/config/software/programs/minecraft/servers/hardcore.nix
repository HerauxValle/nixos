# &desc: "Hardcore Minecraft server -- survival, one life, port 25565. Disabled until the Minecraft vault exists (see autostart.nix)."

{ pkgs, ... }:

{
  services.minecraft-servers.servers.hardcore = {
    enable = false; # flip once `cas Minecraft create`/`2fa on` are done
    package = pkgs.minecraft-server;
    openFirewall = true;
    serverProperties = {
      server-port = 25565;
      gamemode = "survival";
      hardcore = true;
      difficulty = "hard";
      motd = "Hardcore";
    };
  };
}
