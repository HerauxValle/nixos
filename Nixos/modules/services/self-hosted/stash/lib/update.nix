{ cfg, configFile, apply ? false }:

# Checks stashapp/stash's own GitHub releases for something newer than
# cfg.version. Same release asset URL shape as ./package.nix.
#
# apply = false ("@update"): print only, never touches configFile.
# apply = true ("@update:apply"): sed-replaces version/hash in configFile
# directly. configFile is deliberately a plain string, the real
# filesystem path to config/self-hosted/stash.nix -- not a Nix path,
# which would resolve to a read-only /nix/store copy.
#
# Needs curl, jq (GitHub API) and nix (nix-prefetch-url + nix hash
# convert) on PATH -- see stash.nix's mkActionService packages.

''
  set -euo pipefail
  latest="$(curl -sL https://api.github.com/repos/stashapp/stash/releases/latest | jq -r .tag_name | sed 's/^v//')"
  if [ -z "$latest" ] || [ "$latest" = "null" ]; then
    echo "self-hosted-stash: could not check latest release (GitHub API rate limit or network issue)" >&2
    exit 1
  fi
  if [ "$latest" = "${cfg.version}" ]; then
    echo "self-hosted-stash: up to date (${cfg.version})"
    exit 0
  fi
  url="https://github.com/stashapp/stash/releases/download/v''${latest}/stash-linux"
  raw_hash="$(nix-prefetch-url --type sha256 "$url" 2>/dev/null)"
  sri_hash="$(nix hash convert --hash-algo sha256 "$raw_hash")"
''
+ (if apply then ''
  sed -i "s|^\([[:space:]]*\)version = \"[^\"]*\";|\1version = \"$latest\";|" "${configFile}"
  sed -i "s|^\([[:space:]]*\)hash = \"[^\"]*\";|\1hash = \"$sri_hash\";|" "${configFile}"
  echo "self-hosted-stash: applied -- ${configFile} updated (${cfg.version} -> $latest). Rebuild + restart to actually use it."
'' else ''
  echo "self-hosted-stash: update available -- ${cfg.version} -> $latest"
  echo "  version = \"$latest\";"
  echo "  hash = \"$sri_hash\";"
  echo "...or just run @update:apply to write these into ${configFile} directly."
'')
