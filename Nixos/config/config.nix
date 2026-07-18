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

    boot.luks2.usbKeyLabel = "VirtualKeys";

    boot.usbRequired.enable = false;
    boot.usbRequired.usbKeyLabel = "VirtualKeys";

    security.sudoKeyfile.enable = false;

    security.usbKillswitch.killMode = "disabled";
    security.usbKillswitch.usbSerialShort = "0000000000000000000";

    backup.dotfilesBackup.enable = false;
    backup.dotfilesBackup.remoteUrl = "git@github.com:HerauxValle/nixos.git";
    backup.dotfilesBackup.useRepoCache = true;
  };
}
