{ ... }:

# One file (or, for ComfyUI, one folder -- large enough to need
# splitting by concern) per service -- same reasoning as
# modules/services/self-hosted/<name>/ having its own subfolder.
{
  imports = [
    ./comfyui
    ./ollama.nix
    ./openwebui.nix
    ./stash.nix
  ];
}
