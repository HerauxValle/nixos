{ lib, cfg, jellyfinDataDir, waitForApi }:

# postStart step -- installs any declared-but-not-yet-installed plugin
# via Jellyfin's own REST API. Ported from the API-install half of the
# old plugins.sh (its separate flat api-keys-file lookup was not ported
# -- never confirmed to be a real, populated file; see ./wait-for-api.nix
# for the api_key() this uses instead).
#
# Nothing here removes an undeclared-but-installed plugin automatically,
# unlike ComfyUI's nodes/models reconciliation -- Jellyfin's own plugin
# uninstall isn't a simple file deletion (it can leave library metadata
# in an inconsistent state), not safe to automate blind.

let
  installCalls = lib.concatMapStringsSep "\n" (p: ''
    echo "self-hosted-jellyfin-plugins-sync: ensuring ${p.guid} (${p.version})"
    curl -fsSX POST -H "Authorization: MediaBrowser Token=\"$KEY\"" \
      "$(api_url)/Packages/Installed/${p.guid}${lib.optionalString (p.version != "latest") "?version=${p.version}"}" \
      || echo "self-hosted-jellyfin-plugins-sync: install request for ${p.guid} failed (already installed, or a real error -- check the dashboard)" >&2
  '') cfg.plugins;
in
''
  set -euo pipefail
  ${waitForApi}

  if ! wait_for_api; then
    echo "self-hosted-jellyfin-plugins-sync: API did not become ready within 60s -- skipping" >&2
    exit 0
  fi

  KEY="$(api_key)"
  if [ -z "$KEY" ]; then
    echo "self-hosted-jellyfin-plugins-sync: no admin API key yet -- create one via Dashboard -> API Keys -> +, or set JELLYFIN_API_KEY via secrets self-hosted jellyfin (a regular user login does NOT create one) -- skipping"
    exit 0
  fi

  ${installCalls}
''
