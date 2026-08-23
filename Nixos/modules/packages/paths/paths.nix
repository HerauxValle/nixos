# &desc: "PATH-directory exposure logic -- appends config.vars.packages.extraPaths to PATH via environment.extraInit."

{ config, lib, ... }:

# Unlike scripts.nix (which wraps individual files into the store),
# this exposes whole existing directories on PATH as-is -- for
# prebuilt binaries/AppImages you don't want copied into the Nix
# store (large, self-updating, not something you authored).
#
# NOT environment.sessionVariables.PATH -- that REPLACES the whole
# PATH string wholesale (confirmed via `nixos-option`: it collapsed
# the entire system PATH down to just these dirs), it doesn't merge.
# environment.extraInit is the actual append mechanism -- it's the
# same idiom NixOS's own /etc/set-environment uses to tack
# /run/wrappers/bin onto PATH, and it's proven to already reach this
# shell (fish) since that wrapper dir works today.

{
  environment.extraInit = lib.optionalString (config.vars.packages.extraPaths != [ ]) ''
    export PATH="$PATH:${lib.concatStringsSep ":" config.vars.packages.extraPaths}"
  '';
}
