{ pkgs }:

# Pinned straight from filebrowser/filebrowser's own GitHub releases --
# same reasoning as ollama/package.nix and stash/package.nix (own pin,
# not "whatever nixpkgs happens to have"). nixpkgs does package
# `filebrowser` too, but pinning it here keeps this service consistent
# with every other one in this tree (own version/hash, own @update
# check) instead of being the one exception tied to nixpkgs' unrelated
# update schedule.
#
# Confirmed by inspection: the linux-amd64 release tarball's `filebrowser`
# binary is fully static (`ldd` reports "not a dynamic executable") --
# same as stash's, no autoPatchelfHook needed. Verified by building this
# derivation and running the resulting binary's `--help` directly.

{ version, hash }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "filebrowser";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/filebrowser/filebrowser/releases/download/v${version}/linux-amd64-filebrowser.tar.gz";
    inherit hash;
  };

  # The release tarball's entries (filebrowser, LICENSE, README.md,
  # CHANGELOG.md) are flat at its root, no wrapping directory -- stdenv's
  # default unpackPhase expects exactly one top-level directory to `cd`
  # into and fails ("unpacker appears to have produced no directories")
  # otherwise. Confirmed by actually building this derivation.
  unpackPhase = ''
    mkdir -p source
    tar -xzf "$src" -C source
  '';

  installPhase = ''
    mkdir -p "$out/bin"
    cp source/filebrowser "$out/bin/filebrowser"
    chmod +x "$out/bin/filebrowser"
  '';

  meta.mainProgram = "filebrowser";
}
