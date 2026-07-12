{ pkgs, extraBwrapArgs ? [ ] }:

# extraBwrapArgs -- computed in ../comfyui.nix from the currently
# installed nodes, bind-mounts each one's real Nix store source at its
# custom_nodes/<repo> path instead of symlinking it there. See
# ../../self-hosted.nix's mkFHSVenv comment for why.
#
# The FHS sandbox ComfyUI's venv gets created and installed inside --
# same reasoning as openwebui/lib/fhs.nix, just a much heavier targetPkgs
# list: torch+CUDA, plus native-extension-heavy custom nodes that
# compile against a real toolchain (cmake/ninja/gcc), not just link
# against prebuilt wheels. This derivation itself is pure/reproducible
# (a symlink+bind-mount merge, not copies) -- only what pip installs
# inside it, at runtime via preStart's venvEnsureScript, is impure.
#
# python3.12 specifically (confirmed in the old
# configuration/variables/toolchain.sh, same constraint as OpenWebUI).
# GPU access (buildFHSEnv/bubblewrap bind-mounts /run/opengl-driver by
# default) verified empirically, not assumed -- see the actual `bwrap`
# test run against this derivation.

let
  selfHosted = import ../../self-hosted.nix { inherit pkgs; lib = pkgs.lib; };
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
  #   nodes (config/self-hosted/comfyui/catalog/nodes.nix) is git-based, and
  #   the schema doesn't even have a url-node-type option anymore; no
  #   model is a .zip either (checked). Actually dead weight now, not
  #   a faithful-port leftover worth keeping "just in case".
  # - ttf-ms-fonts dropped -- was the old system's attempt at a real
  #   arial.ttf; the font patch (./node-mounting.nix's mkNodeSrc) makes
  #   that moot by pointing the one hardcoded call straight at
  #   dejavu_fonts.
  # - libxcb/libx11 added -- confirmed real gap, not guessed: several
  #   real nodes (was-node-suite-comfyui, ComfyUI-VideoHelperSuite,
  #   SeargeSDXL, ComfyUI-layerdiffuse, ComfyUI-Image-Filters,
  #   ComfyUI-HyperLoRA, comfyui_controlnet_aux, ComfyUI-Impact-Pack,
  #   ComfyUI-Inspire-Pack, facerestore_cf, ComfyUI-SeedVR2_VideoUpscaler,
  #   comfyui-propost, ComfyUI-post-processing-nodes,
  #   ComfyUI-HQ-Image-Save, ComfyUI-Easy-Use, plus the built-in
  #   comfy_extras/nodes_glsl.py) failed to import on a real run with
  #   `libxcb.so.1`/`libX11.so.6: cannot open shared object file` --
  #   opencv-python's compiled extension needs the X11 client libs even
  #   though nothing here has a real display. Old xorg.libxcb/xorg.libX11
  #   names are deprecated in this nixpkgs -- confirmed the current
  #   top-level names (libxcb, libx11) via a real `nix eval`, not
  #   assumed.
  # - e2fsprogs added -- ComfyUI-Hunyuan3DWrapper's pymeshlab dependency
  #   failed with `libcom_err.so.2: cannot open shared object file` on
  #   the same real run. krb5 (the more obvious-looking source of
  #   libcom_err) only ships libcom_err.so.3 in this nixpkgs -- a real
  #   SONAME mismatch, confirmed by actually building both derivations
  #   and listing their lib/ contents, not assumed. e2fsprogs's `.out`
  #   output is the one that actually has libcom_err.so.2.
  # - gmp added -- once libcom_err was fixed, pymeshlab loaded far
  #   enough to reveal a second, previously-hidden missing lib:
  #   libgmp.so.10 (needed by its CGAL-based mesh-boolean plugins),
  #   confirmed on the same real run after the libcom_err fix landed.
  # - p11-kit added -- same story again, a third pymeshlab plugin
  #   (libio_e57.so) needing libp11-kit.so.0, only revealed once gmp was
  #   fixed and it loaded further still. Each of these three was found
  #   by actually running the real service and reading the real error,
  #   one at a time -- not guessed at up front.
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
    libxcb
    libx11
    e2fsprogs
    gmp
    p11-kit
  ];
  inherit extraBwrapArgs;
}
