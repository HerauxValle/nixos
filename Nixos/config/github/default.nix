# &desc: "GitHub dotfiles-backup config imports -- exclusions, redactions (empty), and replacements for published snapshot."

{ ... }:

{
  imports = [
    ./exclusions.nix
    ./redactions.nix
    ./replacements.nix
  ];
}
