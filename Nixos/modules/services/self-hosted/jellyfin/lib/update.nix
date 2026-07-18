# &desc: "Jellyfin update checker -- repo.jellyfin.org latest-stable scrape, prints version/hash, :apply variant edits config."

{ cfg, configFile, apply ? false }:

# Checks repo.jellyfin.org's latest-stable listing for something newer
# than cfg.version. Same release asset URL shape as ./package.nix.
#
# apply = false ("@update"): print only, never touches configFile.
# apply = true ("@update:apply"): sed-replaces version/hash in configFile
# directly. configFile is deliberately a plain string, the real
# filesystem path to config/self-hosted/jellyfin.nix -- not a Nix path,
# which would resolve to a read-only /nix/store copy.
#
# Needs curl, jq (repo listing scrape) and nix (nix-prefetch-url + nix
# hash convert) on PATH -- see jellyfin.nix's mkActionService packages.

''
  set -euo pipefail
  latest="$(curl -fsSL 'https://repo.jellyfin.org/?path=/server/linux/latest-stable/amd64' \
    | grep -oP 'jellyfin_[0-9]+\.[0-9]+\.[0-9]+-amd64\.tar\.gz' \
    | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -V | tail -1)"
  if [ -z "$latest" ]; then
    echo "self-hosted-jellyfin: could not resolve latest version (network issue?)" >&2
    exit 1
  fi
  if [ "$latest" = "${cfg.version}" ]; then
    echo "self-hosted-jellyfin: up to date (${cfg.version})"
    exit 0
  fi
  url="https://repo.jellyfin.org/files/server/linux/latest-stable/amd64/jellyfin_''${latest}-amd64.tar.gz"
  raw_hash="$(nix-prefetch-url --type sha256 "$url" 2>/dev/null)"
  sri_hash="$(nix hash convert --hash-algo sha256 "$raw_hash")"
''
+ (if apply then ''
  sed -i "s|^\([[:space:]]*\)version = \"[^\"]*\";|\1version = \"$latest\";|" "${configFile}"
  sed -i "s|^\([[:space:]]*\)hash = \"[^\"]*\";|\1hash = \"$sri_hash\";|" "${configFile}"
  echo "self-hosted-jellyfin: applied -- ${configFile} updated (${cfg.version} -> $latest). Rebuild + restart to actually use it."
'' else ''
  echo "self-hosted-jellyfin: update available -- ${cfg.version} -> $latest"
  echo "  version = \"$latest\";"
  echo "  hash = \"$sri_hash\";"
  echo "...or just run @update:apply to write these into ${configFile} directly."
'')
