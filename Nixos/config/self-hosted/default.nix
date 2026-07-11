{ ... }:

# One file per service -- config/self-hosted/<name>.nix -- same reasoning
# as modules/services/self-hosted/<name>/ having its own subfolder.
{
  imports = [
    ./ollama.nix
    ./stash.nix
  ];
}
