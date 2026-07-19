# &desc: "Docker daemon (virtualisation.docker) -- the compose/buildx CLI plugins themselves live in packages.nix, not here."

{ ... }:

{
  virtualisation.docker.enable = false;
}
