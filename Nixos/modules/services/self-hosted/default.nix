{ ... }:

# One subfolder per self-hosted service, each a real module declaring its
# own options and logic. ./self-hosted.nix (imported directly by each
# subfolder, not here -- it's a plain function library, not a module) holds
# the part that's actually shared.
{
  imports = [
    ./ollama
    ./stash
  ];
}
