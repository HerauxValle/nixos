{ ... }:

# The dotfiles-backup module's excludeFiles/redactValues -- no sensible
# generic default (this machine's specific sensitive paths/values), same
# reasoning as config/customized.nix, just split into its own file since
# these two lists are bulkier than a flat scalar. See
# modules/backup/dotfiles/default.nix for what each option actually does.
{
  config.vars.dotfilesBackup = {
    # Real values stay in effect locally -- only the published copy has
    # them swapped for a placeholder, and (unlike redactValues) the option
    # stays defined, so the published copy still evaluates/builds cleanly.
    #
    # username/hostName/flake.nix entries: `find` is always the whole
    # line, not just the bare value ("herauxvalle" alone would also match
    # hostName's line above/below in customized.nix, and every other
    # occurrence in flake.nix). flake.nix hardcodes the same username 3
    # separate times (description string, the nixosConfigurations
    # attribute name, and the home-manager.users attribute name) with no
    # exclude/redact/replace coverage of its own -- more exposed than
    # customized.nix since it's the first file anyone opens on a
    # flake-based repo.
    #
    # macAddress: whole-line `find`, not `key` -- the fix is to DROP the
    # override entirely (`= null;`, nixpkgs' own documented "leave empty to
    # use the default" sentinel -- see nixos/modules/tasks/network-interfaces.nix),
    # which needs the surrounding quotes gone too, not just the value
    # between them swapped. A `key`-based bare-value substitution can't do
    # that (it only ever swaps text between the quotes that are already
    # there), so this one has to be the literal whole line, same as
    # username/hostName above.
    #
    # gitCommitEmail/usbSerialShort: `key`, not `find` -- both stay a
    # string-for-string swap inside the existing quotes, so there's no
    # quote-removal problem, and resolving the CURRENT value from config
    # instead of hand-copying it means these two can't silently drift out
    # of sync with customized.nix the way a hand-typed `find` could.
    replaceValues = [
      { file = "Nixos/config/config.nix"; find = ''username = "maxmustermann";''; replaceWith = ''username = "maxmustermann";''; }
      { file = "Nixos/config/config.nix"; find = ''hostName = "nixos";''; replaceWith = ''hostName = "nixos";''; }
      { file = "flake.nix"; find = ''description = "maxmustermann's NixOS config";''; replaceWith = ''description = "maxmustermann's NixOS config";''; }
      { file = "flake.nix"; find = "nixosConfigurations.maxmustermann = nixpkgs.lib.nixosSystem"; replaceWith = "nixosConfigurations.maxmustermann = nixpkgs.lib.nixosSystem"; }
      { file = "flake.nix"; find = "home-manager.users.maxmustermann = import ./Nixos/home.nix;"; replaceWith = "home-manager.users.maxmustermann = import ./Nixos/home.nix;"; }

      { file = "Nixos/modules/system/networking.nix"; find = ''networking.interfaces.''${config.vars.networkInterface}.macAddress = "A8:E6:21:92:2C:E1";''; replaceWith = ''networking.interfaces.''${config.vars.networkInterface}.macAddress = null;''; }

      { file = "Nixos/config/config.nix"; key = "vars.gitCommitEmail"; replaceWith = "maxmustermann@example.com"; }
      { file = "Nixos/config/config.nix"; key = "vars.usbKillswitch.usbSerialShort"; replaceWith = "0000000000000000000"; }

      # Reset the opt-in toggles back to their own off default in the
      # published copy -- customized.nix real values shouldn't imply a
      # stranger cloning this repo also wants your exact security posture
      # turned on. Whole-line `find`, not `key`: usbRequired.enable,
      # sudoKeyfile.enable, and dotfilesBackup.enable are all literally
      # "= true;" in the same file, so a bare-value substitution on "true"
      # would hit all three (and any other "= true;" line) at once instead
      # of just the one meant here.
      { file = "Nixos/config/config.nix"; find = "usbRequired.enable = false;"; replaceWith = "usbRequired.enable = false;"; }
      { file = "Nixos/config/config.nix"; find = "sudoKeyfile.enable = false;"; replaceWith = "sudoKeyfile.enable = false;"; }
      { file = "Nixos/config/config.nix"; find = ''usbKillswitch.killMode = "disabled";''; replaceWith = ''usbKillswitch.killMode = "disabled";''; }
      { file = "Nixos/config/config.nix"; find = "dotfilesBackup.enable = false;"; replaceWith = "dotfilesBackup.enable = false;"; }
    ];
  };
}
