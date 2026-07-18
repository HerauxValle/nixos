#!/usr/bin/env bash

HOSTNAME=$(hostname)
FLAKE_TARGET="/etc/nixos#nixosConfigurations.${HOSTNAME}"

NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 \
NIXPKGS_ALLOW_UNFREE=1 \
NIXPKGS_ALLOW_BROKEN=1 \
nix eval "$FLAKE_TARGET" --impure --json --apply "
  toplevel:
  let
    lib = (import <nixpkgs> {}).lib;

    buildTree = val:
      let
        docList = lib.optionAttrSetToDocList val;
        cleanList = builtins.filter (opt: !(builtins.elem \"_module\" opt.loc)) docList;
      in
      builtins.map (opt: opt.loc) cleanList;
  in
  buildTree toplevel.options.vars
" 2>/dev/null | jq '
  def grow($path; $val):
    if ($path | length) == 0 then
      $val
    else
      . as $node
      | ($path[0]) as $key
      | $node | setpath([$key]; (if ($node[$key] | type) == "object" and ($path | length) > 1 then ($node[$key] | grow($path[1:]; $val)) else ({} | grow($path[1:]; $val)) end))
    end;

  reduce .[] as $p ({}; grow($p; "..."))
'
