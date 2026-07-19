# &desc: "Services config imports -- polkit auth agent, systemd user manager defaults, and the Docker daemon."

{ ... }:

{
  imports = [
    ./docker.nix
    ./polkit.nix
    ./systemd-user-defaults.nix
  ];
}
