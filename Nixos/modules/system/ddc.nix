# &desc: "Declares + wires config.vars.system.ddc (i2c-dev kernel module + ddcutil + i2c group membership) for DDC/CI monitor OSD control from the CLI."

{ config, lib, pkgs, ... }:

# Monitors expose their OSD settings (brightness, contrast, picture mode,
# color temp) over DDC/CI, carried on the same I2C bus the GPU uses for
# EDID reads. The i2c-dev kernel module is what turns that bus into
# /dev/i2c-* device files userspace can talk to; ddcutil is the tool that
# speaks the DDC/CI protocol over those files. Group membership avoids
# needing sudo for every ddcutil call.
{
  options.vars.system.ddc.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Loads i2c-dev, installs ddcutil, and adds config.vars.identity.username to the i2c group for DDC/CI monitor control.";
  };

  config = lib.mkIf config.vars.system.ddc.enable {
    boot.kernelModules = [ "i2c-dev" ];
    environment.systemPackages = [ pkgs.ddcutil ];
    users.groups.i2c = { };
    users.users.${config.vars.identity.username}.extraGroups = [ "i2c" ];
    services.udev.extraRules = ''
      KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
    '';
  };
}
