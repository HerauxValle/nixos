{ ... }:

# The dotfiles-backup module's excludeFiles/redactValues -- no sensible
# generic default (this machine's specific sensitive paths/values), same
# reasoning as config/config.nix, just split into its own file since
# these two lists are bulkier than a flat scalar. See
# modules/backup/dotfiles/default.nix for what each option actually does.
{
  config.vars.backup.dotfilesBackup = {
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
  };
}
