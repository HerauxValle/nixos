{ ... }:

# Split into concern-per-file, same reasoning as the module side --
# ComfyUI's node/model lists are large enough that keeping them in one
# flat comfyui.nix (the way ollama.nix/stash.nix/openwebui.nix do it)
# would bury the actual config values under hundreds of list entries.
# The catalog files (node/model/patch inventories) live in ./catalog/,
# grouped together since they're all the same shape of data.
{
  imports = [
    ./catalog
    ./comfyui.nix
  ];
}
