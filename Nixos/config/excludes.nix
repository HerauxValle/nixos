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

    # Real values (a real MAC, a real email, a real USB serial) stay in
    # effect locally -- only the copy that gets pushed to the public backup
    # repo has them replaced with asterisks. usbSerialShort is the same
    # sensitivity class as the MAC -- a unique physical-hardware identifier,
    # not just a personal preference.
    redactValues = [
      { file = "Nixos/modules/system/networking.nix"; key = "networking.interfaces.enp3s0.macAddress"; }
      { file = "Nixos/config/customized.nix"; key = "vars.gitCommitEmail"; }
      { file = "Nixos/config/customized.nix"; key = "vars.usbKillswitch.usbSerialShort"; }
    ];

    # Real values stay in effect locally -- only the published copy has
    # them swapped for a placeholder. `find` is always the whole line, not
    # just the bare value ("herauxvalle" alone would also match hostName's
    # line above/below in customized.nix, and every other occurrence in
    # flake.nix). flake.nix hardcodes the same username 3 separate times
    # (description string, the nixosConfigurations attribute name, and the
    # home-manager.users attribute name) with no exclude/redact/replace
    # coverage of its own -- more exposed than customized.nix since it's
    # the first file anyone opens on a flake-based repo.
    replaceValues = [
      { file = "Nixos/config/customized.nix"; find = ''username = "maxmustermann";''; replaceWith = ''username = "maxmustermann";''; }
      { file = "Nixos/config/customized.nix"; find = ''hostName = "nixos";''; replaceWith = ''hostName = "nixos";''; }
      { file = "flake.nix"; find = ''description = "maxmustermann's NixOS config";''; replaceWith = ''description = "maxmustermann's NixOS config";''; }
      { file = "flake.nix"; find = "nixosConfigurations.maxmustermann = nixpkgs.lib.nixosSystem"; replaceWith = "nixosConfigurations.maxmustermann = nixpkgs.lib.nixosSystem"; }
      { file = "flake.nix"; find = "home-manager.users.maxmustermann = import ./Nixos/home.nix;"; replaceWith = "home-manager.users.maxmustermann = import ./Nixos/home.nix;"; }
    ];
  };
}
