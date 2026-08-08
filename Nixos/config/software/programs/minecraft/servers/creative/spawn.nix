# &desc: "Creative server's join-spawn behavior -- first-ever join lands in hub, every join after that keeps last location."

{ ... }:

{
  vars.minecraft.servers.creative.startIn = "hub";
  # loginIn left unset -- every join after the first keeps last location.
}
