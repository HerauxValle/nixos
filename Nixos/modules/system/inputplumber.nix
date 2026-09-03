# &desc: "Declares + wires config.vars.system.inputplumber (services.inputplumber daemon) -- system-wide controller-translation, remaps PlayStation/other pads into a virtual XInput device so Wine/Bottles/Proton apps see a gamepad without per-game Steam Input."

{ config, lib, pkgs, ... }:

# One flat file -- same reasoning as ./openrazer.nix. Real value lives in
# config/system/inputplumber.nix.
#
# The upstream binary hardcodes /usr/share/inputplumber as its device-
# profile base path and never consults XDG_DATA_DIRS for it (confirmed via
# RUST_LOG=debug: "No unused configs found for device" for every source,
# because zero .yaml profiles ever load) -- NixOS has no real /usr/share,
# so services.inputplumber.enable alone (just environment.pathsToLink +
# XDG_DATA_DIRS) leaves it blind to every controller, including known
# devices like the PS4/PS5 pad profiles bundled in the package. Its only
# other candidate is /etc/inputplumber/devices.d (+ capability_maps.d),
# which upstream intends as a user-override dir -- populate those with the
# package's own bundled profiles so it actually has something to match
# against.
{
  options.vars.system.inputplumber.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "services.inputplumber.enable.";
  };

  config = lib.mkIf config.vars.system.inputplumber.enable {
    services.inputplumber.enable = true;

    environment.etc."inputplumber/devices.d".source =
      "${pkgs.inputplumber}/share/inputplumber/devices";
    environment.etc."inputplumber/capability_maps.d".source =
      "${pkgs.inputplumber}/share/inputplumber/capability_maps";
  };
}
