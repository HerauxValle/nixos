# &desc: "Creative server's op list -- empty by default, add player names here for admin rights."

{ ... }:

{
  # Emptied temporarily to test the tickfreeze.nix /stopserver command as
  # a real non-op player (LuckPerms default-group permission
  # tickfreeze.toggle, not op status) -- restore "HerauxValle" here once
  # confirmed working.
  vars.minecraft.ops.creative = [ ];
}
