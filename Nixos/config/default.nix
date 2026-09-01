# &desc: "Config directory imports -- personal values, self-hosted services, software, github publishing, system settings, and the standalone gamdl-wrapper service."

{ ... }:

{
  imports = [
    ./config.nix
    ./self-hosted
    ./software
    ./github
    ./system
    ./gamdl
  ];
}
