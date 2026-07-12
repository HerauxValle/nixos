{ config, lib, pkgs, ... }:

# Wiring only -- the package build is ./lib/package.nix, the theme server
# script is ./lib/theme/server.nix, the generic systemd plumbing is
# ../self-hosted.nix. This file's only job is tying those together with
# this service's own config values.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.selfHosted.jellyfin;

  package = import ./lib/package.nix { inherit pkgs; } { inherit (cfg) version hash; };

  ffmpeg = if cfg.ffmpeg != null then cfg.ffmpeg else pkgs.jellyfin-ffmpeg;

  # Root-owned, generic secrets file -- see Scripts/Secrets/cmd/self-hosted.sh
  # (`secrets self-hosted jellyfin`). Two real uses: metadata-provider API
  # keys (TMDB_API_KEY etc -- ready if you set them, but unverified
  # whether Jellyfin actually reads them as env vars, see info.md) and
  # JELLYFIN_API_KEY (a manually-created Jellyfin API key, preferred by
  # wait-for-api.nix's api_key() over the dynamic sqlite lookup).
  environmentFile = "/etc/nixos-secrets/self-hosted/jellyfin/tokens.env";

  waitForApi = import ./lib/wait-for-api.nix { jellyfinDataDir = liveDataDir; };

  # dataDir itself is plain -- config/data/libraries/<name> are each
  # individually storage-backed (see cfg.storage), dataDir is just where
  # their symlinks (and the genuinely-plain cache/transcode/log dirs)
  # live.
  liveDataDir = cfg.dataDir;

  repositoriesXml = pkgs.writeText "jellyfin-repositories.xml" (
    ''<?xml version="1.0" encoding="utf-8"?>''
    + "\n<RepositoryInfos xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">\n"
    + lib.concatMapStringsSep "\n"
      (r: "  <RepositoryInfo>\n    <Name>${r.name}</Name>\n    <Url>${r.url}</Url>\n    <Enabled>true</Enabled>\n  </RepositoryInfo>")
      cfg.pluginRepos
    + "\n</RepositoryInfos>\n"
  );

  themeSyncScript = import ./lib/theme/sync.nix { inherit cfg waitForApi; jellyfinDataDir = liveDataDir; };
  pluginsSyncScript = import ./lib/plugins-sync.nix { inherit lib cfg waitForApi; jellyfinDataDir = liveDataDir; };
  rescanScript = import ./lib/rescan.nix { jellyfinDataDir = liveDataDir; };

  # Plain string, not a Nix path -- see update.nix for why (resolves to a
  # read-only /nix/store copy otherwise, this needs to be the real
  # writable location for @update:apply to sed-edit).
  jellyfinConfigFile = "${config.vars.homeDirectory}/Dotfiles/Nixos/config/self-hosted/jellyfin.nix";
  updateScript = import ./lib/update.nix { inherit cfg; configFile = jellyfinConfigFile; };
  updateApplyScript = import ./lib/update.nix { inherit cfg; configFile = jellyfinConfigFile; apply = true; };

in

{
  config = lib.mkMerge [
    (selfHosted.mkSelfHostedService {
      name = "jellyfin";
      enabled = cfg.enabled;
      user = config.vars.username;
      homeDirectory = config.vars.homeDirectory;
      execStart = "${package}/bin/jellyfin"
        + " --datadir \"${liveDataDir}/data\""
        + " --configdir \"${liveDataDir}/config\""
        + " --cachedir \"${liveDataDir}/cache\""
        + " --logdir \"${liveDataDir}/log\""
        + " --webdir \"${package}/lib/jellyfin/jellyfin-web\""
        + " --ffmpeg \"${ffmpeg}/bin/ffmpeg\"";
      preStart = [
        # Plain scratch dirs -- never storage-backed, safe to mkdir -p
        # unconditionally every start.
        ''mkdir -p "${liveDataDir}/cache" "${liveDataDir}/transcode" "${liveDataDir}/log"''
      ]
      # Pure filesystem, deterministic from cfg.pluginRepos -- no live
      # process needed for this part (unlike actually installing a
      # plugin, which does, see postStart below). Guarded on a non-empty
      # list -- Jellyfin ships the official repo built in on its own; an
      # unconditional write with an empty list risks overwriting that
      # default with nothing, unconfirmed whether that's actually safe.
      ++ lib.optionals (cfg.pluginRepos != [ ]) [
        ''
          mkdir -p "${liveDataDir}/config"
          cp -f "${repositoriesXml}" "${liveDataDir}/config/repositories.xml"
        ''
      ];
      postStart =
        lib.optionals (cfg.themeServer.enable && cfg.themeServer.themeDir != null) [ themeSyncScript ]
        ++ lib.optionals (cfg.plugins != [ ]) [ pluginsSyncScript ];
      packages = [ pkgs.sqlite pkgs.curl pkgs.python3 ];
      ensureDataDir = true; # dataDir itself is plain, safe to auto-create
      inherit (cfg) dataDir storage autoStart environment requireMounts teardownPaths;
      limitNoFile = cfg.fdLimit;
      inherit environmentFile;
    })
    (selfHosted.mkActionService {
      name = "jellyfin";
      enabled = cfg.enabled;
      user = config.vars.username;
      # curl+jq/nix for update's release-listing scrape + hash prefetch;
      # sqlite+curl+python3 for rescan's DB surgery + API calls.
      packages = [ pkgs.curl pkgs.jq pkgs.nix pkgs.sqlite pkgs.python3 pkgs.gnugrep ];
      inherit environmentFile;
      actions = {
        update = updateScript;
        "update:apply" = updateApplyScript;
        rescan = rescanScript;
      };
    })
    # The theme server -- a separate, minimal systemd unit (not through
    # mkSelfHostedService, which has none of that machinery's needs: no
    # dataDir/storage/requireMounts/postStart, just a tiny static file
    # server). PartOf ties its lifecycle to the main service (stopping
    # jellyfin stops this too, matching the old run_stop() stopping both
    # together); wantedBy follows jellyfin's own autoStart.
    (lib.mkIf (cfg.enabled && cfg.themeServer.enable && cfg.themeServer.themeDir != null) {
      systemd.services."self-hosted-jellyfin-theme" = {
        description = "self-hosted: jellyfin theme server";
        partOf = [ "self-hosted-jellyfin.service" ];
        wantedBy = lib.optionals cfg.autoStart [ "multi-user.target" ];
        serviceConfig = {
          User = config.vars.username;
          ExecStart = "${pkgs.python3}/bin/python3 ${import ./lib/theme/server.nix { inherit pkgs; }} ${cfg.themeServer.bindAddress} ${toString cfg.themeServer.port} ${cfg.themeServer.themeDir}";
          Restart = "on-failure";
        };
      };
    })
  ];
}
