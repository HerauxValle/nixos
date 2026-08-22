# &desc: "Ollama binary package builder -- fetchurl GitHub release tarball (zstd), bundles libcublas/libcudart/libggml-cuda, addDriverRunpath for host libcuda."

{ pkgs }:

# Pinned straight from ollama's own GitHub releases -- not "whatever
# nixpkgs happens to have packaged" (that only works when a package
# exists at all, and ties the version to nixpkgs' own unrelated
# schedule). Same recipe modules/hyprland/plugins/plugins.nix's mkPlugin
# already uses for Hyprland plugins (a pinned rev/hash fetched straight
# from source), applied to a release asset instead of a git rev.
#
# Confirmed by inspection: the release tarball bundles its own
# libcublas/libcudart/libggml-cuda .so files (both CUDA 12 and 13), so
# this needs nothing from pkgs.cudaPackages -- only addDriverRunpath, to
# find the *host's actual installed* libcuda.so at runtime (that one can
# never be bundled, it has to match the real driver). Verified by
# building this derivation and running the resulting binary directly.

{ version, hash }:

pkgs.stdenv.mkDerivation {
  pname = "ollama";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/ollama/ollama/releases/download/v${version}/ollama-linux-amd64.tar.zst";
    inherit hash;
  };

  nativeBuildInputs = [ pkgs.zstd pkgs.autoPatchelfHook pkgs.addDriverRunpath ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib ];

  # libcuda.so.1 is the *host's* real driver, never bundled by anyone --
  # addDriverRunpath still points the RPATH at /run/opengl-driver/lib so
  # it resolves at actual runtime, this just tells autoPatchelfHook not
  # to hard-fail the build over a lib that can never be present in the
  # sandbox. libvulkan.so.1 is only wanted by the bundled Vulkan backend,
  # which this module doesn't use (CUDA only) -- same reasoning.
  autoPatchelfIgnoreMissingDeps = [ "libcuda.so.1" "libvulkan.so.1" ];

  unpackPhase = ''
    mkdir -p source
    tar --zstd -xf "$src" -C source
  '';

  installPhase = ''
    mkdir -p "$out"
    cp -r source/bin "$out/bin"
    cp -r source/lib "$out/lib"
  '';

  # autoPatchelfHook's own postFixup hook runs *after* this attribute and
  # unconditionally `patchelf --set-rpath`s every ELF it touches
  # (including cuda_v12/cuda_v13/libggml-cuda.so), which clobbers any
  # addDriverRunpath addition made here first. Confirmed via build log:
  # our loop left no trace, and autoPatchelf's own "setting RPATH to: ..."
  # lines for those files came after, missing /run/opengl-driver/lib.
  # dontAutoPatchelf + calling `autoPatchelf` ourselves first forces the
  # order the other way: patchelf sets deps-based RPATH, *then*
  # addDriverRunpath appends the host driver path on top, so it survives.
  dontAutoPatchelf = true;
  postFixup = ''
    autoPatchelf "$out"
    for so in "$out"/lib/ollama/cuda_v12/*.so "$out"/lib/ollama/cuda_v13/*.so; do
      addDriverRunpath "$so"
    done
  '';

  meta.mainProgram = "ollama";
}
