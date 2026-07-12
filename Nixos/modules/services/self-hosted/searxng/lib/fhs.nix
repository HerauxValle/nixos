{ pkgs }:

# The FHS sandbox SearXNG's venv gets created and installed inside --
# needed because pip-installed compiled wheels (lxml) expect real /lib,
# /usr/lib paths that don't exist on NixOS. This derivation itself is
# pure/reproducible (a symlink+bind-mount merge of the packages below,
# not copies) -- only what pip installs inside it, at runtime via
# preStart's venvEnsureScript, is impure. See ../../self-hosted.nix's
# mkFHSVenv, which this is a thin wrapper around with this service's own
# targetPkgs.
#
# python3.12 -- SearXNG's own setup.py declares python_requires ">=3.10"
# (up to 3.13 in its trove classifiers), 3.12 matches every other
# venv-based service in this tree. git is needed here too (not just on
# the action-service side) -- preStart's own srcEnsureScript clones/
# checks out coreRev using the sandbox's own git, same reasoning as
# needing libxml2/libxslt for lxml.

let
  selfHosted = import ../../self-hosted.nix { inherit pkgs; lib = pkgs.lib; };
in

selfHosted.mkFHSVenv {
  name = "searxng";
  targetPkgs = pkgs: with pkgs; [
    python312
    stdenv.cc.cc.lib
    zlib
    libxml2
    libxslt
    openssl
    git
  ];
}
