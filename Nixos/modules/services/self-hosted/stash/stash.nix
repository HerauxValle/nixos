{ config, lib, pkgs, ... }:

# Wiring only -- the package build is ./package.nix, the generic systemd
# plumbing is ../self-hosted.nix. This file's only job is tying those
# together with this service's own config values.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.selfHosted.stash;

  package = import ./lib/package.nix { inherit pkgs; } { inherit (cfg) version hash; };

  # dataDir itself is a plain, always-available path (same convention as
  # every other service) -- it holds nothing on its own now that the
  # binary comes from the Nix store, it's just where cfg.storage's
  # symlink(s) land. Stash only ever has one real data location (its
  # first/only storage entry) -- that's a Stash-specific fact, not a
  # limitation of storage itself, which stays a plain list.
  liveDataDir = "${cfg.dataDir}/${(builtins.head cfg.storage).src}";

  # Stash writes into several subdirectories of its data dir on its own,
  # but never creates them itself -- same mkdir set the old runtime.sh
  # did before every start.
  dataSubdirs = [ "plugins" "scrapers" "metadata" "cache" "generated" "blobs" ];

  # Plain string, not a Nix path -- see update.nix for why (resolves to a
  # read-only /nix/store copy otherwise, this needs to be the real
  # writable location for @update:apply to sed-edit).
  stashConfigFile = "${config.vars.homeDirectory}/Dotfiles/Nixos/config/self-hosted/stash.nix";
  updateScript = import ./lib/update.nix { inherit cfg; configFile = stashConfigFile; };
  updateApplyScript = import ./lib/update.nix { inherit cfg; configFile = stashConfigFile; apply = true; };

in

{
  config = lib.mkMerge [
    (selfHosted.mkSelfHostedService {
      name = "stash";
      enabled = cfg.enabled;
      user = config.vars.username;
      homeDirectory = config.vars.homeDirectory;
      execStart = "${pkgs.writeShellScript "self-hosted-stash-start" ''
        cd "${liveDataDir}"
        exec ${package}/bin/stash --host ${cfg.host} --port ${toString cfg.port}
      ''}";
      preStart = [
        "mkdir -p ${lib.concatMapStringsSep " " (d: "${liveDataDir}/${d}") dataSubdirs}"
      ];
      ensureDataDir = true; # dataDir itself is plain now, safe to auto-create
      inherit (cfg) dataDir storage autoStart environment requireMounts teardownPaths;
    })
    (selfHosted.mkActionService {
      name = "stash";
      enabled = cfg.enabled;
      user = config.vars.username;
      # curl+jq for the GitHub releases API, nix for
      # nix-prefetch-url/nix hash convert -- only @update needs these.
      packages = [ pkgs.curl pkgs.jq pkgs.nix ];
      # Stash has no venv and no declarative models/nodes -- nothing to
      # install or sync, so those actions don't exist here at all.
      actions = {
        update = updateScript;
        "update:apply" = updateApplyScript;
      };
    })
  ];
}
