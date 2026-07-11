{ pkgs }:

# Pinned straight from stashapp/stash's own GitHub releases -- same
# reasoning as ollama/package.nix. Confirmed by inspection: the
# `stash-linux` release asset is a fully static Go binary (no dynamic
# deps at all, `ldd` reports "statically linked") -- no autoPatchelfHook
# needed, unlike ollama's CUDA-linked build. Verified by building this
# derivation and running the resulting binary directly (`--version`).

{ version, hash }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "stash";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/stashapp/stash/releases/download/v${version}/stash-linux";
    inherit hash;
  };

  dontUnpack = true;

  installPhase = ''
    mkdir -p "$out/bin"
    cp "$src" "$out/bin/stash"
    chmod +x "$out/bin/stash"
  '';

  meta.mainProgram = "stash";
}
