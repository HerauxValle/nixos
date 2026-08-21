# &desc: "Declares + wires config.vars.system.openrazer (hardware.openrazer daemon + group membership) for Razer mouse button/lighting control."

{ config, lib, ... }:

# One flat file -- same reasoning as ./hidden-devices.nix, this doesn't
# grow complex enough to earn a default.nix/lib split. Real values live
# in config/system/openrazer.nix.
#
# hardware.openrazer.enable pulls in the kernel driver + userspace
# daemon (org.razer over DBus); pkgs.polychromatic (config/software/
# packages/packages.nix) is the GUI that talks to that daemon for
# button remapping/macros/lighting. Group membership goes through
# hardware.openrazer.users, not users.users.<name>.extraGroups -- the
# upstream module owns users.groups.openrazer.members itself.
{
  options.vars.system.openrazer.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "hardware.openrazer.enable + adds config.vars.identity.username to the openrazer group.";
  };

  config = lib.mkIf config.vars.system.openrazer.enable {
    hardware.openrazer = {
      enable = true;
      users = [ config.vars.identity.username ];
    };
  };
}
