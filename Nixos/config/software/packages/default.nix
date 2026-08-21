# &desc: "Software packages config imports -- personal selections and package source registry."

{ ... }:

{
  imports = [
    ./packages.nix
    ./registry.nix
  ];
}
