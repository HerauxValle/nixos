{ pkgs, apply ? false }:

# Print-only, both forms -- same reasoning as Immich's own update.nix:
# the package tracks nixpkgs' own pkgs.qbittorrent-nox, not a version/
# hash pinned in this repo, so there's nothing local for @update:apply
# to write. Needs curl+jq on PATH -- see qbittorrent.nix's
# mkActionService packages.

let
  currentVersion = pkgs.qbittorrent-nox.version;
in
''
  set -euo pipefail
  latest="$(curl -sL https://api.github.com/repos/qbittorrent/qBittorrent/releases/latest | jq -r .tag_name | sed 's/^release-//')"
  if [ -z "$latest" ] || [ "$latest" = "null" ]; then
    echo "self-hosted-qbittorrent: could not check latest release (GitHub API rate limit or network issue)" >&2
    exit 1
  fi
  if [ "$latest" = "${currentVersion}" ]; then
    echo "self-hosted-qbittorrent: up to date -- nixpkgs tracks ${currentVersion}, matches upstream's latest release"
    exit 0
  fi
  echo "self-hosted-qbittorrent: nixpkgs-tracked version (${currentVersion}) is behind upstream's latest release ($latest)"
''
+ (if apply then ''
  echo "self-hosted-qbittorrent: nothing to write -- this service tracks nixpkgs' own pkgs.qbittorrent-nox, not a version/hash pinned in this repo."
  echo "  To actually update: bump this flake's nixpkgs input from Dotfiles/, e.g.:"
  echo "    nix flake lock --update-input nixpkgs"
  echo "  then nixos-rebuild switch + restart (systemctl restart qbittorrent)."
'' else ''
  echo "  nixpkgs' own pkgs.qbittorrent-nox may still lag this -- expected, same tradeoff as any nixpkgs-tracked package."
  echo "  Run @update:apply for instructions on how to actually get a newer one."
'')
