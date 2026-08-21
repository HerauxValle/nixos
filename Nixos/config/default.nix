# &desc: "Config directory imports -- personal values, self-hosted services, software, github publishing, and system settings."

{ ... }:

{
  imports = [
    ./config.nix
    ./self-hosted
    ./software
    ./github
    ./system
  ];
}
