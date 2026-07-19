# &desc: "Makes VS Code's settings.json writable after Home Manager links it in -- otherwise VS Code throws an EROFS dialog on every launch trying to write to the read-only Nix store symlink."

{ config, inputs, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.home.activation = {
    # Home Manager refuses to relink settings.json over the writable copy
    # left by vscodeWritableSettings below -- clear it first so
    # linkGeneration can freely place the fresh symlink.
    vscodeSettingsUnlink = inputs.home-manager.lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      settingsFile="$HOME/.config/Code/User/settings.json"
      if [ -e "$settingsFile" ] && [ ! -L "$settingsFile" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$settingsFile"
      fi
    '';

    # VS Code writes to settings.json at runtime (setting migrations,
    # extension state, etc) and throws an EROFS error dialog on every
    # launch if it's left as the default read-only Nix store symlink.
    # Swap it for a writable copy of the same content right after Home
    # Manager links it in -- still regenerated from ./*.nix on every
    # rebuild, just no longer read-only in between rebuilds.
    vscodeWritableSettings = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      settingsFile="$HOME/.config/Code/User/settings.json"
      if [ -L "$settingsFile" ]; then
        target=$(${pkgs.coreutils}/bin/readlink -f "$settingsFile")
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$settingsFile"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp "$target" "$settingsFile"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod u+w "$settingsFile"
      fi
    '';
  };
}
