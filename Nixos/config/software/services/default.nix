# &desc: "Services config imports -- polkit auth agent, systemd-resolved, systemd user manager defaults, and the Docker daemon."

{ ... }:

{
  imports = [
    ./docker.nix
    ./polkit.nix
    ./resolved.nix
    ./systemd-user-defaults.nix
  ];
}
