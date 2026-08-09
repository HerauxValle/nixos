# &desc: "Declares config.vars.minecraft.prism.{portable,location} -- logic that wires the symlink activation lives in ./minecraft-prism.nix. Real values live in config/software/programs/prism/default.nix."

{ lib, ... }:

{
  imports = [ ./minecraft-prism.nix ];

  options.vars.minecraft.prism = {
    portable = lib.mkEnableOption "relocating all Prism Launcher data (instances, mods, worlds, cfg, themes, icons) to vars.minecraft.prism.location";

    location = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Directory that becomes Prism Launcher's entire data root when
        portable is enabled. No default -- this is a personal path choice,
        not something this repo should assume for anyone cloning it; must
        be set explicitly alongside portable = true.
      '';
    };
  };
}
