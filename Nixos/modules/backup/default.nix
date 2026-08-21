# &desc: "Backup module root -- imports dotfiles GitHub backup submodule."

{ config, pkgs, ... }:

{
  imports = [
    ./dotfiles
  ];
}
