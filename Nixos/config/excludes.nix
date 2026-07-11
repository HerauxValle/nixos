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
    ];

    # Real values (a real MAC, a real email) stay in effect locally --
    # only the copy that gets pushed to the public backup repo has them
    # replaced with asterisks.
    redactValues = [
      { file = "Nixos/modules/system/networking.nix"; key = "networking.interfaces.enp3s0.macAddress"; }
      { file = "Nixos/config/customized.nix"; key = "vars.gitCommitEmail"; }
    ];
  };
}
