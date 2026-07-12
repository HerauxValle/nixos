{ lib, selfHosted, cfg, requirementsIn, requirementsLock, requirementsLockPath, configFile }:

# Returns an attrset merged straight into odysseus.nix's `actions` --
# Odysseus has two independent things that can go stale (the pinned
# core commit, the dependency lock), same shape as SearXNG's update.nix.
#
# update            -- core, then deps.
# update:core       -- just the pinned odysseus core commit (coreRev).
# update:deps       -- re-run pip-compile, diff against the checked-in
#                       lock (see ../../self-hosted.nix's mkDepsUpdateScript).

let

  mkCoreCheckScript = { apply ? false }: ''
    set -euo pipefail
    latest_rev="$(git ls-remote https://github.com/pewdiepie-archdaemon/odysseus HEAD | cut -f1)"
    if [ -z "$latest_rev" ]; then
      echo "self-hosted-odysseus: could not check core (network issue?)" >&2
      exit 1
    fi
    if [ "$latest_rev" = "${cfg.coreRev}" ]; then
      echo "self-hosted-odysseus: core is up to date (${cfg.coreRev})"
    else
      echo "self-hosted-odysseus: core update available -- ${cfg.coreRev} -> $latest_rev"
  ''
  + (if apply then ''
      sed -i "s|^\([[:space:]]*\)coreRev = \"[^\"]*\";|\1coreRev = \"''${latest_rev}\";|" "${configFile}"
      echo "self-hosted-odysseus: applied -- core ${cfg.coreRev} -> $latest_rev in ${configFile}. Rebuild + restart to actually check it out."
    fi
  '' else ''
      echo "  coreRev = \"$latest_rev\";"
      echo "...or just run @update:core:apply to write this into ${configFile} directly."
    fi
  '');

  mkDepsCheckScript = { apply ? false }: selfHosted.mkDepsUpdateScript {
    serviceName = "odysseus";
    inherit requirementsIn requirementsLock requirementsLockPath apply;
  };

  mkAllActions = { apply ? false }:
    (mkCoreCheckScript { inherit apply; })
    + "\n" + (mkDepsCheckScript { inherit apply; });

in

{
  update = mkAllActions { apply = false; };
  "update:apply" = mkAllActions { apply = true; };
  "update:core" = mkCoreCheckScript { apply = false; };
  "update:core:apply" = mkCoreCheckScript { apply = true; };
  "update:deps" = mkDepsCheckScript { apply = false; };
  "update:deps:apply" = mkDepsCheckScript { apply = true; };
}
