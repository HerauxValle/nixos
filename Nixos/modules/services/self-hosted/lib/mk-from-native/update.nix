{ pkgs }:

# Shared print-only update.nix body for every mk-from-native service --
# Immich and QBitTorrent both had byte-for-byte identical update.nix
# files except for five real per-service facts (name, the package
# attribute to read .version from, the upstream GitHub repo, that
# repo's release-tag prefix, and which real systemd unit(s) to mention
# restarting) -- deduplicated here once a second real caller confirmed
# the pattern, not speculatively.
#
# Same reasoning as every other mk-from-native service's own
# update.nix: the package tracks nixpkgs' own pkgs.<name>, not a
# version/hash pinned in this repo, so there's nothing local for
# @update:apply to write -- both actions still exist (every service
# gets update/update:apply, per docs/conventions.md), just with a
# narrower job: report current vs latest, and (apply) explain how to
# actually get a newer one instead of writing anything. Needs curl+jq
# on the caller's own mkActionService packages.
{ name
  # The real package derivation itself (e.g. pkgs.immich,
  # pkgs.qbittorrent-nox) -- only its .version is read, but the whole
  # derivation is taken (not just a version string) so a caller never
  # has to keep name/version in sync by hand.
, package
  # "owner/repo" on GitHub -- releases/latest is queried directly.
, githubRepo
  # Regex/sed pattern stripped from the front of the release tag to get
  # a bare version string -- real values seen so far: "v" (Immich's
  # tags are "v2.8.0") and "release-" (qBittorrent's are
  # "release-5.2.3"). No generic default -- there's no "usual" prefix,
  # every upstream project picks its own convention.
, tagPrefix
  # Real unit name(s) to mention restarting, e.g. "immich-server
  # immich-machine-learning" or "qbittorrent" -- a plain string, not a
  # list, since the exact wording ("systemctl restart X Y") is
  # service-specific enough that forcing a list-join convention here
  # wouldn't save anything real.
, restartUnits
, apply ? false
}:
let
  currentVersion = package.version;
in
''
  set -euo pipefail
  latest="$(curl -sL https://api.github.com/repos/${githubRepo}/releases/latest | jq -r .tag_name | sed 's/^${tagPrefix}//')"
  if [ -z "$latest" ] || [ "$latest" = "null" ]; then
    echo "self-hosted-${name}: could not check latest release (GitHub API rate limit or network issue)" >&2
    exit 1
  fi
  if [ "$latest" = "${currentVersion}" ]; then
    echo "self-hosted-${name}: up to date -- nixpkgs tracks ${currentVersion}, matches upstream's latest release"
    exit 0
  fi
  echo "self-hosted-${name}: nixpkgs-tracked version (${currentVersion}) is behind upstream's latest release ($latest)"
''
+ (if apply then ''
  echo "self-hosted-${name}: nothing to write -- this service tracks nixpkgs' own package, not a version/hash pinned in this repo."
  echo "  To actually update: bump this flake's nixpkgs input from Dotfiles/, e.g.:"
  echo "    nix flake lock --update-input nixpkgs"
  echo "  then nixos-rebuild switch + restart (systemctl restart ${restartUnits})."
  echo "  Note: nixpkgs' own package may still lag upstream's very latest release after that -- expected for any nixpkgs-tracked package, same tradeoff as every other one on this machine."
'' else ''
  echo "  nixpkgs' own package may still lag this after a bump -- expected, same tradeoff as any nixpkgs-tracked package."
  echo "  Run @update:apply for instructions on how to actually get a newer one."
'')
