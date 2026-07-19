# &desc: "Personal machine configuration values -- identity, boot, security, services, packages, and system settings."

{ ... }:

# Your actual personal values -- the one real definition for every option
# declared as required (no sensible generic default) across Nixos/modules/.
# One flat file since these are all small scalars; bulkier customizations
# (the package list, scripts list, shells list, dotfiles-backup
# excludes/redactions) get their own dedicated files alongside this one
# instead of bloating it.
{
  config.vars = {
    identity = {
      username = "maxmustermann";
      hostName = "nixos";
      networkInterface = "enp3s0";
      timeZone = "Europe/Berlin";
      stateVersion = "26.05";
      gitCommitEmail = "maxmustermann@example.com";
    };

    boot = {
      luks2.usbKeyLabel = "VirtualKeys";
      usbRequired.enable = false;
      usbRequired.usbKeyLabel = "VirtualKeys";

      # Temporarily visible (default is hidden, revealed with ESC) --
      # while disko is being dry-built/wired alongside
      # hardware-configuration.nix (see partitioning.nix), a real
      # countdown menu means rollback to the previous generation doesn't
      # depend on catching an ESC-press window under pressure if a
      # switch ever goes wrong. Safe to flip back to true once that
      # verification work is done.
      grub.hidden = false;
    };

    security = {
      sudoKeyfile.enable = false;
      usbKillswitch.killMode = "disabled";
      usbKillswitch.usbSerialShort = "0000000000000000000";
    };

    backup.dotfilesBackup = {
      enable = false; 
      remoteUrl = "git@github.com:HerauxValle/nixos.git";
      useRepoCache = true;
    };
  };

  # Real values for vars.alias -- schema lives in
  # ../modules/alias.nix. Empty by default; add an entry here to shorten
  # a deeply-nested vars.* path you reference often.
  config.vars.alias = {
    # Example (uncomment to try it):
    # testUsername = config.vars.identity.username;
  };
}
