# &desc: "PATH-directory exposure logic -- appends config.vars.packages.extraPaths to PATH via environment.extraInit, warns if a session restart is needed."

{ config, lib, pkgs, ... }:

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
#
# extraInit only gets sourced by fresh login shells -- confirmed live
# that Hyprland (and everything it spawns, e.g. MyBar/quickshell)
# inherits whatever PATH it had at ITS OWN launch and never re-reads
# it, so a plain rebuild silently does nothing for anything already
# running in that session. Same diff-against-/run/booted-system
# activationScript pattern as modules/system/hidden-devices.nix's
# [udev] notice, keyed on set-environment (where extraInit lands)
# instead of udev rules.

{
  environment.extraInit = lib.optionalString (config.vars.packages.extraPaths != [ ]) ''
    export PATH="$PATH:${lib.concatStringsSep ":" config.vars.packages.extraPaths}"
  '';

  system.activationScripts.pathRestartNotice = {
    text = ''
      bootedSetEnv=/run/booted-system/etc/set-environment
      if [ -e "$bootedSetEnv" ] && ! ${pkgs.diffutils}/bin/diff -q "${config.system.build.etc}/etc/set-environment" "$bootedSetEnv" >/dev/null 2>&1; then
        echo -e "\033[0;31m[path] Some settings require a session (Hyprland) restart to take effect.\033[0m"
      fi
    '';
  };
}
