# &desc: "Hardcore server's autostart setting -- explicit false, server must be started manually -- plus tick-freeze default."

{ ... }:

{
  # Explicit, not just relying on the default -- no auto-start on boot,
  # start it yourself with `systemctl start minecraft-server-hardcore`.
  vars.minecraft.servers.hardcore.autostart = false;

  # Migrated from creative/ (its own tickFreeze = true stays as-is,
  # untouched) after confirming the mechanism there 2026-08-10: ticks
  # pause via vanilla /tick freeze once no one's online, /stopserver
  # on|off toggles it live in-game via LuckPerms default-group
  # permission tickfreeze.toggle (ops.nix already keeps hardcore
  # permanently op-less, so this is the real, natural test of the
  # non-op grant, not creative's temporary deop). See
  # modules/services/minecraft-worlds/tickfreeze.nix.
  vars.minecraft.servers.hardcore.tickFreeze = true;
}
