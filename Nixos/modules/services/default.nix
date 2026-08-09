# &desc: "Services module root -- imports self-hosted services framework and Minecraft world creation schema."

{ ... }:

{
  imports = [
    ./minecraft-worlds
    ./minecraft-prism
    ./self-hosted
  ];
}
