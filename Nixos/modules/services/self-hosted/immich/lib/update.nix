{ pkgs, apply ? false }:

# Print-only, both forms -- unlike every other service's update.nix
# (ollama/jellyfin/etc.), there's no configFile to sed here: Immich's
# package tracks nixpkgs' own pkgs.immich (see default.nix's own
# comment), not a version/hash pinned in this repo, so there's nothing
# local for @update:apply to write. Both actions still exist -- every
# service gets update/update:apply, per docs/conventions.md -- just with
# a narrower job: report current vs latest, and (apply) explain how to
# actually get a newer one instead of writing anything.
#
# Needs curl+jq on PATH -- see immich.nix's mkActionService packages.

let
  currentVersion = pkgs.immich.version;
in
''
  set -euo pipefail
  latest="$(curl -sL https://api.github.com/repos/immich-app/immich/releases/latest | jq -r .tag_name | sed 's/^v//')"
  if [ -z "$latest" ] || [ "$latest" = "null" ]; then
    echo "self-hosted-immich: could not check latest release (GitHub API rate limit or network issue)" >&2
    exit 1
  fi
  if [ "$latest" = "${currentVersion}" ]; then
    echo "self-hosted-immich: up to date -- nixpkgs tracks ${currentVersion}, matches upstream's latest release"
    exit 0
  fi
  echo "self-hosted-immich: nixpkgs-tracked version (${currentVersion}) is behind upstream's latest release ($latest)"
''
+ (if apply then ''
  echo "self-hosted-immich: nothing to write -- this service tracks nixpkgs' own pkgs.immich, not a version/hash pinned in this repo."
  echo "  To actually update: bump this flake's nixpkgs input from Dotfiles/, e.g.:"
  echo "    nix flake lock --update-input nixpkgs"
  echo "  then nixos-rebuild switch + restart (systemctl restart immich-server immich-machine-learning)."
  echo "  Note: nixpkgs' own pkgs.immich may still lag upstream's very latest release after that -- expected for any nixpkgs-tracked package, same tradeoff as every other one on this machine."
'' else ''
  echo "  nixpkgs' own pkgs.immich may still lag this after a bump -- expected, same tradeoff as any nixpkgs-tracked package."
  echo "  Run @update:apply for instructions on how to actually get a newer one."
'')
