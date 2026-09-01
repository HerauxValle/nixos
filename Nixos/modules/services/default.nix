# &desc: "Services module root -- imports self-hosted services framework, Minecraft world creation schema, and the standalone gamdl-wrapper service."

{ ... }:

{
  imports = [
    ./minecraft-worlds
    ./minecraft-prism
    ./self-hosted
    ./gamdl
  ];
}
