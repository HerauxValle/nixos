# &desc: "Steam program config -- enable, remote play + LAN game transfer firewall opened."

{ ... }:

{
  config.vars.packages.programs.steam = {
    enable = true;
    remotePlayOpenFirewall = true;
    localNetworkGameTransfersOpenFirewall = true;
  };
}
