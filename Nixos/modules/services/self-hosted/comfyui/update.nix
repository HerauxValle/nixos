{ lib, selfHosted, cfg, activeNodes, comfyRequirementsIn, requirementsLock, requirementsLockPath, configFile, nodesFile }:

# Returns an attrset merged straight into comfyui.nix's `actions` --
# ComfyUI is the one service with three independent things that can go
# stale (core, each pinned node, the dependency lock), so "update" isn't
# a single script the way it is for the other services.
#
# Every check below exists in two forms:
#   update[:core|:nodes|:nodes:REPO|:deps]         -- print/diff only
#   update[:core|:nodes|:nodes:REPO|:deps]:apply    -- writes the change
# configFile/nodesFile are deliberately plain strings, the real
# filesystem paths to config/self-hosted/comfyui/{comfyui,nodes}.nix --
# not Nix paths, which would resolve to read-only /nix/store copies.
#
# update            -- core, then installed nodes, then deps.
# update:core       -- just the pinned ComfyUI core commit.
# update:nodes      -- every *installed* node (cfg.installed.nodes) --
#                       matches what @sync:nodes actually keeps in sync.
# update:nodes:REPO -- one specific node, by `repo` -- works for any
#                       node in nodeStore, installed or not.
# update:deps       -- re-run pip-compile, diff against the checked-in
#                       lock (see ../self-hosted.nix's mkDepsUpdateScript).

let

  mkNodeCheckScript = { node, apply ? false }: ''
    set -euo pipefail
    latest_rev="$(git ls-remote "https://github.com/${node.owner}/${node.repo}" HEAD | cut -f1)"
    if [ -z "$latest_rev" ]; then
      echo "self-hosted-comfyui: could not check ${node.repo} (network issue?)" >&2
      exit 1
    fi
    if [ "$latest_rev" = "${node.rev}" ]; then
      echo "self-hosted-comfyui: ${node.repo} is up to date (${node.rev})"
    else
      hash="$(nix-prefetch-git --url "https://github.com/${node.owner}/${node.repo}" --rev "$latest_rev" --quiet | jq -r .hash)"
  ''
  + (if apply then ''
      sed -i "s|{ owner = \"${node.owner}\"; repo = \"${node.repo}\"; rev = \"[^\"]*\"; hash = \"[^\"]*\"; }|{ owner = \"${node.owner}\"; repo = \"${node.repo}\"; rev = \"''${latest_rev}\"; hash = \"''${hash}\"; }|" "${nodesFile}"
      echo "self-hosted-comfyui: applied -- ${node.repo} ${node.rev} -> $latest_rev in ${nodesFile}"
    fi
  '' else ''
      echo "self-hosted-comfyui: ${node.repo} update available -- ${node.rev} -> $latest_rev"
      echo "  rev = \"$latest_rev\"; hash = \"$hash\";"
    fi
  '');

  mkCoreCheckScript = { apply ? false }: ''
    set -euo pipefail
    latest_rev="$(git ls-remote https://github.com/comfyanonymous/ComfyUI HEAD | cut -f1)"
    if [ -z "$latest_rev" ]; then
      echo "self-hosted-comfyui: could not check core (network issue?)" >&2
      exit 1
    fi
    if [ "$latest_rev" = "${cfg.coreRev}" ]; then
      echo "self-hosted-comfyui: core is up to date (${cfg.coreRev})"
    else
      hash="$(nix-prefetch-git --url https://github.com/comfyanonymous/ComfyUI --rev "$latest_rev" --quiet | jq -r .hash)"
  ''
  + (if apply then ''
      sed -i "s|^\([[:space:]]*\)coreRev = \"[^\"]*\";|\1coreRev = \"''${latest_rev}\";|" "${configFile}"
      sed -i "s|^\([[:space:]]*\)coreHash = \"[^\"]*\";|\1coreHash = \"''${hash}\";|" "${configFile}"
      echo "self-hosted-comfyui: applied -- core ${cfg.coreRev} -> $latest_rev in ${configFile}"
    fi
  '' else ''
      echo "self-hosted-comfyui: core update available -- ${cfg.coreRev} -> $latest_rev"
      echo "  coreRev = \"$latest_rev\";"
      echo "  coreHash = \"$hash\";"
    fi
  '');

  mkDepsCheckScript = { apply ? false }: selfHosted.mkDepsUpdateScript {
    serviceName = "comfyui";
    requirementsIn = comfyRequirementsIn;
    inherit requirementsLock requirementsLockPath apply;
  };

  mkInstalledNodeChecks = { apply ? false }:
    lib.concatMapStringsSep "\n" (node: mkNodeCheckScript { inherit node apply; }) activeNodes;

  mkPerNodeActions = { apply ? false, suffix }:
    lib.listToAttrs (map
      (node: {
        name = "update:nodes:${node.repo}${suffix}";
        value = mkNodeCheckScript { inherit node apply; };
      })
      cfg.nodeStore);

  mkAllActions = { apply ? false }:
    (mkCoreCheckScript { inherit apply; })
    + "\n" + (mkInstalledNodeChecks { inherit apply; })
    + "\n" + (mkDepsCheckScript { inherit apply; });

in

(mkPerNodeActions { apply = false; suffix = ""; })
// (mkPerNodeActions { apply = true; suffix = ":apply"; })
// {
  update = mkAllActions { apply = false; };
  "update:apply" = mkAllActions { apply = true; };
  "update:core" = mkCoreCheckScript { apply = false; };
  "update:core:apply" = mkCoreCheckScript { apply = true; };
  "update:nodes" = mkInstalledNodeChecks { apply = false; };
  "update:nodes:apply" = mkInstalledNodeChecks { apply = true; };
  "update:deps" = mkDepsCheckScript { apply = false; };
  "update:deps:apply" = mkDepsCheckScript { apply = true; };
}
