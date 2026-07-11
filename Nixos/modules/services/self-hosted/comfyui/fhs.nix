{ pkgs, extraBwrapArgs ? [ ] }:

# extraBwrapArgs -- computed in ./comfyui.nix from the currently
# installed nodes, bind-mounts each one's real Nix store source at its
# custom_nodes/<repo> path instead of symlinking it there. See
# ../self-hosted.nix's mkFHSVenv comment for why.
#
# The FHS sandbox ComfyUI's venv gets created and installed inside --
# same reasoning as openwebui/fhs.nix, just a much heavier targetPkgs
# list: torch+CUDA, plus native-extension-heavy custom nodes that
# compile against a real toolchain (cmake/ninja/gcc), not just link
# against prebuilt wheels. This derivation itself is pure/reproducible
# (a symlink+bind-mount merge, not copies) -- only what pip installs
# inside it, at runtime via the @install action, is impure.
#
# python3.12 specifically (confirmed in the old
# configuration/variables/toolchain.sh, same constraint as OpenWebUI).
# GPU access (buildFHSEnv/bubblewrap bind-mounts /run/opengl-driver by
# default) verified empirically, not assumed -- see the actual `bwrap`
# test run against this derivation.

let
  selfHosted = import ../self-hosted.nix { inherit pkgs; lib = pkgs.lib; };
in

selfHosted.mkFHSVenv {
  name = "comfyui";
  # Ported from the old REQUIRED_ARCH_PKGS, checked against what's
  # actually still relevant rather than copied blind:
  # - libGLU added -- old list had "glu", missed in the first pass;
  #   the 3D/mesh nodes (Hunyuan3DWrapper, SAM3DBody) are the likely
  #   users.
  # - unzip dropped -- old plugins.sh supported a "url" node type that
  #   unzipped downloaded archives, but every one of the 69 declared
  #   nodes (config/self-hosted/comfyui/nodes.nix) is git-based, and
  #   the schema doesn't even have a url-node-type option anymore; no
  #   model is a .zip either (checked). Actually dead weight now, not
  #   a faithful-port leftover worth keeping "just in case".
  # - ttf-ms-fonts dropped -- was the old system's attempt at a real
  #   arial.ttf; the font patch (./comfyui.nix's mkNodeSrc) makes that
  #   moot by pointing the one hardcoded call straight at dejavu_fonts.
  targetPkgs = pkgs: with pkgs; [
    python312
    stdenv.cc
    cmake
    ninja
    gcc
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
    ffmpeg
    libGL
    libGLU
    mesa
    glib
    zlib
    git
    dejavu_fonts
    noto-fonts
  ];
  inherit extraBwrapArgs;
}
