# &desc: "Creative server's join-spawn behavior -- first-ever join lands in hub, every join after that keeps last location."

{ ... }:

{
  # "<world>" (Multiverse's own world-spawn point) or "<world> x y z"
  # (exact coordinates within that world) -- e.g. "hub 0 65 0". Coords
  # must be all three or none; mixing e.g. just x is a config error
  # (caught at build time by minecraft-worlds.nix's parseDestination).
  vars.minecraft.servers.creative.startIn = "hub";

  # loginIn left unset -- every join after the first keeps last location.
  # Would use the exact same "<world>" / "<world> x y z" syntax as
  # startIn above if set.
}
