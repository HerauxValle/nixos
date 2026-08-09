# &desc: "VS Code enable -- fully declarative (mutableExtensionsDir = false), extensions/keybindings/settings managed entirely by Nix. Also clears stale userdata hot-exit backups every rebuild."

{ config, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory).
  config.home-manager.users.${config.vars.identity.username}.programs.vscode = {
    enable = true;
    # Extensions are fully declared in ../extensions -- don't let VS Code's
    # own UI install/mutate extensions outside of Nix.
    mutableExtensionsDir = false;
  };

  # settings.json/keybindings.json are symlinks into the Nix store (read-only),
  # so VS Code can never save its own hot-exit backups for them -- but it still
  # creates one in Backups/<hash>/vscode-userdata/ whenever the buffer gets
  # marked dirty (e.g. autoSave firing on a stale/restored tab). Once that
  # backup exists, VS Code restores it as a dirty buffer on every future
  # launch and immediately fails to autosave it (EROFS), forever. Since both
  # files are 100% Nix-managed, any such backup is always stale garbage --
  # move it out of the way (never delete outright) on every rebuild so it
  # can never accumulate.
  #
  # A home-manager home.activation script was tried here first, but NixOS
  # only restarts home-manager-<user>.service (and so only re-runs its
  # activation scripts) when home-manager's OWN config changed -- a
  # system-only rebuild leaves it untouched, so a fresh backup VS Code
  # created in between silently never gets cleared. system.activationScripts
  # instead run unconditionally on every single `nixos-rebuild switch`, no
  # restart-trigger diffing involved, which is what's actually needed here.
  # These run as root, hence the explicit chown back to the user afterward.
  config.system.activationScripts.clearVscodeUserdataBackups.text =
    let
      homeDir = config.vars.identity.homeDirectory;
      username = config.vars.identity.username;
    in
    ''
      vscodeStaleBackupDest="${homeDir}/.backup/vscode"
      for vscodeStaleUserdataDir in "${homeDir}"/.config/Code/Backups/*/vscode-userdata; do
        if [ -d "$vscodeStaleUserdataDir" ]; then
          printf '\033[0;31m[vscode] stale userdata found -- cleared and moved into %s\033[0m\n' "$vscodeStaleBackupDest"
          mkdir -p "$vscodeStaleBackupDest"
          mv "$vscodeStaleUserdataDir" "$vscodeStaleBackupDest/$(basename "$(dirname "$vscodeStaleUserdataDir")")-$(date +%s)"
          chown -R ${username}:users "$vscodeStaleBackupDest"
        fi
      done
    '';
}
