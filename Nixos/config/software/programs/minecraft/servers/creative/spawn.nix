# &desc: "Creative server's join-spawn behavior -- first-ever join lands in hub, every join after that keeps last location. Also autostart=false explicit -- server must be started manually."

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

  # Explicit, not just relying on the default -- no auto-start on boot,
  # start it yourself with `systemctl start minecraft-server-creative`.
  vars.minecraft.servers.creative.autostart = false;

  # Test bed for the tick-freeze feature (modules/services/minecraft-
  # worlds/tickfreeze.nix) before migrating it to hardcore/ -- see that
  # file for the full mechanism. true = armed by default (ticks pause
  # while no one's online); /stopserver on|off toggles it live in-game
  # (LuckPerms default-group permission tickfreeze.toggle, no op
  # needed), but that's ephemeral -- every restart/rebuild resets back
  # to true.
  vars.minecraft.servers.creative.tickFreeze = true;
}
