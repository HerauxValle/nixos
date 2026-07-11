{ ... }:

# Your actual personal values -- the one real definition for every option
# declared as required (no sensible generic default) across Nixos/modules/.
# One flat file since these are all small scalars; bulkier customizations
# (the package list, scripts list, shells list, dotfiles-backup
# excludes/redactions) get their own dedicated files alongside this one
# instead of bloating it.
{
  config.vars = {
    username = "maxmustermann";
    hostName = "nixos";
    timeZone = "Europe/Berlin";
    stateVersion = "26.05";
    gitCommitEmail = "***************************";

    luks2.usbKeyLabel = "VirtualKeys";
    usbRequired.usbKeyLabel = "VirtualKeys";
    usbKillswitch.usbSerialShort = "*******************";
    dotfilesBackup.remoteUrl = "git@github.com:HerauxValle/nixos.git";
  };
}
