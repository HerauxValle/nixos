{ ... }:

# One subfolder per self-hosted service, each a real module declaring its
# own options and logic. ./self-hosted.nix (imported directly by each
# subfolder, not here -- it's a plain function library, not a module) holds
# the part that's actually shared. Read ./docs/ before adding a new
# service or changing shared behavior -- how everything works, how to add
# a service, and the rules that keep this generalized without
# over-generalizing.
{
  imports = [
    ./comfyui
    ./ollama
    ./openwebui
    ./stash
  ];
}
