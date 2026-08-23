# &desc: "extraPaths schema -- empty default, personal picks merged from config/paths.nix via Nix option merge. Wrapping logic in ./paths.nix."

{ lib, ... }:

{
  imports = [ ./paths.nix ];

  options.vars.packages.extraPaths = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Directories of prebuilt/unmanaged binaries (AppImages etc) to add to PATH as-is, without copying into the Nix store. See modules/packages/paths/paths.nix.";
  };
}
