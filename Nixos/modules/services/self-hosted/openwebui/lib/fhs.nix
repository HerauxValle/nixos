{ pkgs }:

# The FHS sandbox open-webui's venv gets created and installed inside --
# needed because pip-installed compiled wheels (pillow, lxml) expect real
# /lib, /usr/lib paths that don't exist on NixOS. This derivation itself
# is pure/reproducible (a symlink+bind-mount merge of the packages below,
# not copies) -- only what pip installs inside it, at runtime via
# preStart's venvEnsureScript, is impure. See ../../self-hosted.nix's
# mkFHSVenv, which this is a thin wrapper around with this service's own
# targetPkgs.
#
# python3.12 specifically, not generic python3 -- open-webui requires
# >=3.11,<3.13 (confirmed in the old
# configuration/variables/toolchain.sh).

let
  selfHosted = import ../../self-hosted.nix { inherit pkgs; lib = pkgs.lib; };
in

selfHosted.mkFHSVenv {
  name = "openwebui";
  targetPkgs = pkgs: with pkgs; [
    python312
    stdenv.cc.cc.lib
    zlib
    libjpeg
    libxml2
    libxslt
    openssl
    git
  ];
}
