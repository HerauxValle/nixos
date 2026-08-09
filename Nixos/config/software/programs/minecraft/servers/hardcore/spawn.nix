# &desc: "Hardcore server's autostart setting -- explicit false, server must be started manually."

{ ... }:

{
  # Explicit, not just relying on the default -- no auto-start on boot,
  # start it yourself with `systemctl start minecraft-server-hardcore`.
  vars.minecraft.servers.hardcore.autostart = false;
}
