# &desc: "Script PATH exposure schema -- generic default is pacnix (manages repo), personal picks merged from config/scripts.nix via Nix option merge."

{ lib, ... }:

# Schema (empty default -- an always-valid, always-safe fallback) plus the
# one entry that's a genuine generic default: pacnix manages this exact
# repo's own NixOS config, so anyone using this repo wants it on PATH
# regardless of personal preference. Everything else (which scripts YOU
# personally want exposed) is pure customization -- see
# Nixos/config/scripts.nix, concatenated with this file's list (Nix's own
# listOf-option merge behavior, not a custom mechanism). Wrapping logic
# lives in ./scripts.nix, imported below.
{
  imports = [ ./scripts.nix ];

  options.vars.packages.scripts = lib.mkOption {
    type = lib.types.listOf lib.types.attrs;
    default = [ ];
    description = "Folders to expose specific files from as PATH commands. See modules/packages/scripts/scripts.nix for the wrapping logic.";
  };

  config.vars.packages.scripts = [
    {
      dir = ../../../../Scripts/Pacnix;
      include = {
        "main.sh" = "pacnix";
      };
    }
  ];
}
