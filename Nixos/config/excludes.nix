{ ... }:

# The dotfiles-backup module's excludeFiles/redactValues -- no sensible
# generic default (this machine's specific sensitive paths/values), same
# reasoning as config/customized.nix, just split into its own file since
# these two lists are bulkier than a flat scalar. See
# modules/backup/dotfiles/default.nix for what each option actually does.
{
  config.vars.dotfilesBackup = {
    excludeFiles = [
      "Shells/Fish/secrets.fish"
      ".envrc"

      # Local-only variable reference -- reproduces several of the real
      # values redacted/replaced elsewhere (gitCommitEmail, username,
      # usbSerialShort) as plain-text documentation, so publishing it would
      # undo those. Excluding the whole file is simpler and more robust
      # than mirroring every redactValues/replaceValues entry a second
      # time just for a doc, and it doesn't need to be public anyway.
      "Nixos/index.md"
    ];

    # Empty for now -- redactValues' mask-and-comment-out treatment only
    # stays safe for values that are genuinely OPTIONAL (a missing/commented
    # definition just falls back to that option's own default). Every value
    # that used to live here (the MAC, gitCommitEmail, usbSerialShort) is a
    # REQUIRED option (no default) or gets re-resolved by this exact module
    # against a config that no longer defines it -- commenting either out
    # leaves the published copy unable to even evaluate. Confirmed live: this
    # is exactly what broke before they moved to replaceValues below. Kept
    # as a real option (not removed) for any future value that's actually
    # optional and fine being fully blanked out.
    redactValues = [ ];

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
      { file = "Nixos/config/customized.nix"; find = ''username = "maxmustermann";''; replaceWith = ''username = "maxmustermann";''; }
      { file = "Nixos/config/customized.nix"; find = ''hostName = "nixos";''; replaceWith = ''hostName = "nixos";''; }
      { file = "flake.nix"; find = ''description = "maxmustermann's NixOS config";''; replaceWith = ''description = "maxmustermann's NixOS config";''; }
      { file = "flake.nix"; find = "nixosConfigurations.maxmustermann = nixpkgs.lib.nixosSystem"; replaceWith = "nixosConfigurations.maxmustermann = nixpkgs.lib.nixosSystem"; }
      { file = "flake.nix"; find = "home-manager.users.maxmustermann = import ./Nixos/home.nix;"; replaceWith = "home-manager.users.maxmustermann = import ./Nixos/home.nix;"; }

      { file = "Nixos/modules/system/networking.nix"; find = ''networking.interfaces.enp3s0.macAddress = null;''; replaceWith = "networking.interfaces.enp3s0.macAddress = null;"; }

      { file = "Nixos/config/customized.nix"; key = "vars.gitCommitEmail"; replaceWith = "maxmustermann@example.com"; }
      { file = "Nixos/config/customized.nix"; key = "vars.usbKillswitch.usbSerialShort"; replaceWith = "0000000000000000000"; }
    ];
  };
}
