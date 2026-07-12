{ ... }:

# One subfolder per self-hosted service, each a real module declaring its
# own options and logic. ./self-hosted.nix (imported directly by each
# subfolder, not here -- it's a plain function library, not a module) holds
# the part that's actually shared. Read ./docs/ before adding a new
# service or changing shared behavior -- how everything works, how to add
# a service, and the rules that keep this generalized without
# over-generalizing.
#
# ./lib is here too, one folder down like everything else -- it has its
# own default.nix that reaches one further folder down into
# ./lib/acl-traversal (the one lib/ entry with real options of its own).
# Nothing in this file ever reaches two levels down itself.
{
  imports = [
    ./comfyui
    ./filebrowser
    ./immich
    ./jellyfin
    ./lib
    ./odysseus
    ./ollama
    ./openwebui
    ./qbittorrent
    ./searxng
    ./stash
  ];
}
