# &desc: "Module directory root -- imports all schema submodules and defines vars.alias shortcut mechanism."

{ lib, ... }:

{
  imports = [
    ./backup
    ./boot
    ./desktop
    ./hyprland
    ./nix
    ./packages
    ./security
    ./services
    ./system
  ];

  # Schema only -- a free-form bucket for shortcuts to deeply-nested vars.*
  # paths. Real values (the actual name -> value entries) live in
  # Nixos/config/vars-alias.nix, same modules/ (schema) vs config/ (data)
  # split as everywhere else in this repo.
  #
  # Read-through only, not a bidirectional alias like lib.mkAliasOptionModule
  # -- config.vars.alias.<name> is just a plain option whose value happens to
  # reference another option (same mechanism variables.nix's own
  # homeDirectory default already uses), not a forwarded option in its own
  # right. Setting config.vars.alias.<name> itself doesn't write back to the
  # real path; only reading through it works.
  options.vars.alias = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
    description = ''
      Shortcuts for deeply-nested vars.* paths -- set in
      Nixos/config/vars-alias.nix, e.g.
      config.vars.alias.ollamaHost = config.vars.services.selfHosted.ollama.host;
      then use config.vars.alias.ollamaHost anywhere instead of the long path.
    '';
  };
}
