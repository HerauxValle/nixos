# &desc: "Odysseus FHS sandbox builder -- python314 (matching vault venv), lxml/libxml2/libxslt (for XML parsing), pillow/libjpeg (qrcode[pil])."

{ pkgs }:

# The FHS sandbox Odysseus's venv gets created and installed inside --
# needed because pip-installed compiled wheels (bcrypt, cryptography,
# lxml, pillow, onnxruntime, grpcio, numpy) expect real /lib, /usr/lib
# paths that don't exist on NixOS. This derivation itself is
# pure/reproducible (a symlink+bind-mount merge of the packages below,
# not copies) -- only what pip installs inside it, at runtime via
# preStart's venvEnsureScript, is impure. See ../../self-hosted.nix's
# mkFHSVenv, which this is a thin wrapper around with this service's own
# targetPkgs.
#
# python314, not python312 like Ollama/OpenWebUI/SearXNG -- the real,
# already-working venv recovered from the vault (pyvenv.cfg) was built
# against 3.14.5, and Odysseus's own README only states "Python 3.11+"
# with no upper bound, so there's no reason to downgrade from what was
# actually last confirmed working. lxml/libxml2/libxslt (transitively
# pulled in, confirmed via requirements.lock, not directly required by
# requirements.in) and pillow/libjpeg (qrcode[pil]) are the same real
# needs SearXNG/OpenWebUI's own fhs.nix already established. git is
# needed here too, not just on the action-service side -- preStart's own
# srcEnsureScript clones/checks out coreRev using the sandbox's own git,
# same reasoning as SearXNG's.
let
  selfHosted = import ../../self-hosted.nix { inherit pkgs; lib = pkgs.lib; };
in

selfHosted.mkFHSVenv {
  name = "odysseus";
  targetPkgs = pkgs: with pkgs; [
    python314
    stdenv.cc.cc.lib
    zlib
    libjpeg
    libxml2
    libxslt
    openssl
    git
  ];
}
