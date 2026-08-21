# &desc: "Self-hosted services config imports -- one file per service plus ComfyUI subfolder, includes acl-traversal."

{ ... }:

# One file (or, for ComfyUI, one folder -- large enough to need
# splitting by concern) per service -- same reasoning as
# modules/services/self-hosted/<name>/ having its own subfolder.
{
  imports = [
    ./acl-traversal.nix
    ./comfyui
    ./filebrowser.nix
    ./immich.nix
    ./jellyfin.nix
    ./odysseus.nix
    ./ollama.nix
    ./openwebui.nix
    ./qbittorrent.nix
    ./searxng.nix
    ./stash.nix
  ];
}
