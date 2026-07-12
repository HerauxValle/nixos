{ ... }:

# One file (or, for ComfyUI, one folder -- large enough to need
# splitting by concern) per service -- same reasoning as
# modules/services/self-hosted/<name>/ having its own subfolder.
{
  imports = [
    ./comfyui
    ./filebrowser.nix
    ./jellyfin.nix
    ./ollama.nix
    ./openwebui.nix
    ./searxng.nix
    ./stash.nix
  ];
}
