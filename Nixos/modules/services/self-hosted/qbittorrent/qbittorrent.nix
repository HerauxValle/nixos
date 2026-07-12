{ config, lib, pkgs, ... }:

# Wiring only -- same shape as immich.nix: no package.nix (pkgs.
# qbittorrent-nox comes straight from nixpkgs, see default.nix's own
# version comment) and the live unit is built entirely by
# services.qbittorrent itself, not by mkSelfHostedService.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.selfHosted.qbittorrent;

  updateScript = import ./lib/update.nix { inherit pkgs; };
  updateApplyScript = import ./lib/update.nix { inherit pkgs; apply = true; };

  serverConfig = lib.recursiveUpdate cfg.extraServerConfig (
    {
      LegalNotice.Accepted = true;
      BitTorrent.Session = {
        DefaultSavePath = cfg.paths.save;
      } // lib.optionalAttrs (cfg.paths.temp != null) {
        TempPath = cfg.paths.temp;
        TempPathEnabled = true;
      } // lib.optionalAttrs (cfg.paths.export != null) {
        TorrentExportDirectory = cfg.paths.export;
      } // lib.optionalAttrs (cfg.paths.finished != null) {
        FinishedTorrentExportDirectory = cfg.paths.finished;
      };
    }
    // lib.optionalAttrs (cfg.host != null) {
      Preferences.WebUI.Address = cfg.host;
    }
  );

in

{
  config = lib.mkMerge [
    (selfHosted.mkFromNativeService {
      enabled = cfg.enabled;
      requireMounts = cfg.requireMounts;
      mountCheckUnits = [ "qbittorrent" ];
      extraConfig = {
        services.qbittorrent = {
          enable = false;
          inherit (cfg) profileDir webuiPort;
          inherit serverConfig;
        }
        // lib.optionalAttrs (cfg.torrentingPort != null) { torrentingPort = cfg.torrentingPort; };

        # services.qbittorrent hardcodes wantedBy = [ "multi-user.target" ]
        # and ProtectHome = "yes" -- no autoStart-equivalent option
        # exists natively, and ProtectHome hides profileDir (vault-
        # backed, under /home) from the unit entirely. Both real,
        # confirmed problems this session already found and fixed the
        # identical way for Immich -- mkForce wins over the unconditioned
        # wantedBy, ProtectHome = "tmpfs" + BindPaths (reusing
        # requireMounts, same as immich.nix) fixes the mount visibility.
        # savePath/tempPath live on the external Storage drive
        # (/run/media/..., not under /home at all), so they're
        # unaffected by ProtectHome either way.
        systemd.services.qbittorrent.wantedBy =
          lib.mkForce (lib.optionals cfg.autoStart [ "multi-user.target" ]);
        systemd.services.qbittorrent.serviceConfig.ProtectHome = lib.mkForce "tmpfs";
        systemd.services.qbittorrent.serviceConfig.BindPaths = cfg.requireMounts;

        # Real bug, found on a live run: profileDir (and its own
        # qBittorrent/ subfolder) ended up root:root -- a side effect of
        # an earlier failed start attempt creating it before this whole
        # chain of fixes existed. The wrapped module's own tmpfiles
        # rules (systemd.tmpfiles.settings.qbittorrent, `d` type) only
        # fix ownership *at creation time* -- they don't correct
        # already-wrong ownership on an existing path the way `Z` does,
        # and don't cover profileDir itself at all, only the nested
        # qBittorrent/ and qBittorrent/config/ paths inside it. Same
        # fix, same reasoning as Immich's own mediaLocation: a
        # recursive `Z` rule, every activation, idempotent.
        systemd.tmpfiles.rules = [
          "Z ${cfg.profileDir} 0750 ${config.services.qbittorrent.user} ${config.services.qbittorrent.group} - -"
        ];
      };
    })
    (selfHosted.mkActionService {
      name = "qbittorrent";
      enabled = cfg.enabled;
      user = config.vars.username;
      packages = [ pkgs.curl pkgs.jq ];
      actions = {
        update = updateScript;
        "update:apply" = updateApplyScript;
      };
    })
  ];
}
