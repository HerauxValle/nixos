{ config, lib, pkgs, ... }:

# Wiring only -- the package build is ./lib/package.nix, the generic
# systemd plumbing is ../self-hosted.nix. This file's only job is tying
# those together with this service's own config values.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.services.selfHosted.filebrowser;

  package = import ./lib/package.nix { inherit pkgs; } { inherit (cfg) version hash; };

  # dataDir itself is a plain, always-available path (same convention as
  # every other service) -- it holds nothing on its own, it's just where
  # cfg.storage's symlink lands. FileBrowser only ever has one real data
  # location (its first/only storage entry) -- that's a FileBrowser-
  # specific fact, not a limitation of storage itself, which stays a
  # plain list. Same shape as Stash's liveDataDir.
  liveDataDir = "${cfg.dataDir}/${(builtins.head cfg.storage).src}";
  dbFile = "${liveDataDir}/filebrowser.db";

  # Plain string, not a Nix path -- see update.nix for why (resolves to a
  # read-only /nix/store copy otherwise, this needs to be the real
  # writable location for @update:apply to sed-edit).
  filebrowserConfigFile = "${config.vars.identity.homeDirectory}/Dotfiles/Nixos/config/self-hosted/filebrowser.nix";
  updateScript = import ./lib/update.nix { inherit cfg; configFile = filebrowserConfigFile; };
  updateApplyScript = import ./lib/update.nix { inherit cfg; configFile = filebrowserConfigFile; apply = true; };

in

{
  config = lib.mkMerge [
    (selfHosted.mkSelfHostedService {
      name = "filebrowser";
      enabled = cfg.enabled;
      user = config.vars.identity.username;
      homeDirectory = config.vars.identity.homeDirectory;
      execStart = "${pkgs.writeShellScript "self-hosted-filebrowser-start" ''
        cd "${liveDataDir}"
        exec ${package}/bin/filebrowser -d "${dbFile}" -a "${cfg.host}" -p "${toString cfg.port}"
      ''}";
      # Faithful port of the old install.sh: the database only gets
      # `config init`'d the first time it doesn't exist yet -- root is
      # baked in at that point (config init -r), never passed again on
      # later starts (matches the original runtime.sh's plain -d/-a/-p
      # invocation, no -r). If a recovered/pre-existing filebrowser.db is
      # already at dbFile (see storage below), this whole block is a
      # no-op and whatever was already configured in it wins, same as
      # every other service's preStart reconciliation.
      preStart = [
        ''
          mkdir -p "${liveDataDir}"
          if [ ! -f "${dbFile}" ]; then
            ${package}/bin/filebrowser -d "${dbFile}" config init -r "${cfg.root}"
            ${package}/bin/filebrowser -d "${dbFile}" config set -a "${cfg.host}" -p "${toString cfg.port}"
          fi
        ''
      ];
      ensureDataDir = true; # dataDir itself is plain, safe to auto-create
      inherit (cfg) dataDir storage autoStart environment requireMounts teardownPaths;
    })
    (selfHosted.mkActionService {
      name = "filebrowser";
      enabled = cfg.enabled;
      user = config.vars.identity.username;
      # curl+jq for the GitHub releases API, nix for
      # nix-prefetch-url/nix hash convert -- only @update needs these.
      packages = [ pkgs.curl pkgs.jq pkgs.nix ];
      # No venv, no declarative reconciliation list -- nothing to install
      # or sync here, same as Stash.
      actions = {
        update = updateScript;
        "update:apply" = updateApplyScript;
      };
    })
  ];
}
