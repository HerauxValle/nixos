# &desc: "Services config imports -- polkit auth agent and systemd user manager defaults."

{ ... }:

{
  imports = [
    ./polkit.nix
    ./systemd-user-defaults.nix
  ];
}
