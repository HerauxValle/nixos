{ ... }:

# Every file here is "catalog data" in the same sense: a full inventory
# of things that may or may not currently be active (nodeStore/
# modelStore vs installed.nodes/installed.models), plus patches.nix --
# which is exactly the same shape (a fix keyed by repo, only ever
# relevant for a repo that's actually installed) even though it isn't
# filtered through its own separate installed.* list the way nodes/
# models are; it piggybacks on installed.nodes instead (see
# comfyui.nix's activeNodePatches). Grouped into their own subdirectory
# once comfyui/ passed the ~4-5-files-per-dir point this repo aims for.
{
  imports = [
    ./nodes.nix
    ./models.nix
    ./patches.nix
  ];
}
