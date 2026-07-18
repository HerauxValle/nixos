#!/usr/bin/env bash

# Get the current system hostname
HOSTNAME=$(hostname)

# Define the Nix flake target
FLAKE_TARGET="/etc/nixos#nixosConfigurations.${HOSTNAME}.options.vars"

echo "Evaluating NixOS configuration for ${HOSTNAME}... (this might take a second)" >&2

# 1. Run nix eval to extract the option paths, ignoring internal module junk
# 2. Use the local jq command to robustly construct the nested JSON tree
NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 \
NIXPKGS_ALLOW_UNFREE=1 \
NIXPKGS_ALLOW_BROKEN=1 \
nix eval "$FLAKE_TARGET" --impure --json --apply '
  val:
  let
    lib = (import <nixpkgs> {}).lib;
    docList = lib.optionAttrSetToDocList val;
    cleanList = builtins.filter (opt: !(builtins.elem "_module" opt.loc)) docList;
  in
  builtins.map (opt: opt.loc) cleanList
' 2>/dev/null | jq '
  reduce .[] as $path ({};
    reduce range(1; $path | length) as $i (.;
      setpath($path[0:$i]; getpath($path[0:$i]) // {})
    )
    | setpath($path; if getpath($path) == {} then {} else "..." end)
  )
'
