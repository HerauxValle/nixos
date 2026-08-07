# &desc: "Creative Minecraft testworld server -- peaceful, creative mode, port 25566. Disabled until the Minecraft vault exists (see autostart.nix)."

{ pkgs, ... }:

{
  services.minecraft-servers.servers.testworld = {
    enable = false; # flip once `cas Minecraft create`/`2fa on` are done
    package = pkgs.minecraft-server;
    openFirewall = true;
    serverProperties = {
      server-port = 25566;
      gamemode = "creative";
      difficulty = "peaceful";
      motd = "Testworld";
    };
  };
}
