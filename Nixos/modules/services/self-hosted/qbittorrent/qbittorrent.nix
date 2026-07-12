{ config, lib, pkgs, ... }:

# Wiring only -- same shape as immich.nix: no package.nix (pkgs.
# qbittorrent-nox comes straight from nixpkgs, see default.nix's own
# version comment) and the live unit is built entirely by
# services.qbittorrent itself, not by mkSelfHostedService.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.selfHosted.qbittorrent;

  # Shared with every other mk-from-native service's own update.nix --
  # see ../lib/mk-from-native/update.nix's own top comment (deduped once
  # this and Immich's were confirmed byte-for-byte identical except for
  # these five facts).
  updateArgs = {
    name = "qbittorrent";
    package = pkgs.qbittorrent-nox;
    githubRepo = "qbittorrent/qBittorrent";
    tagPrefix = "release-";
    restartUnits = "qbittorrent";
  };
  updateScript = selfHosted.mkFromNativeUpdateScript updateArgs;
  updateApplyScript = selfHosted.mkFromNativeUpdateScript (updateArgs // { apply = true; });

  liveConf = "${cfg.profileDir}/qBittorrent/config/qBittorrent.conf";
  webuiBackupFile = "${cfg.profileDir}/.webui-settings.bak";

  # A stranger cloning this repo (or this machine, before ever running
  # `secrets qbittorrent`) shouldn't have to go spelunking through
  # `journalctl -u qbittorrent` for a random one-session temp password
  # just to reach the WebUI at all -- lowest-priority layer in
  # serverConfig below, so any real WebUI.Username/Password_PBKDF2 from
  # extraServerConfig (config/self-hosted/qbittorrent.nix's own, once
  # `secrets qbittorrent` generates one) wins over this the instant one
  # exists. admin/"changeme" -- verified against qBittorrent's real
  # PBKDF2-HMAC-SHA512/100000-iteration/16-byte-salt scheme, not typed
  # in blind (see `secrets qbittorrent`'s own comment for the algorithm
  # source).
  defaultWebui = {
    WebUI = {
      Username = "admin";
      Password_PBKDF2 = "@ByteArray(ZUySNa1CFPOSQBoNAzUbOg==:PST2x7yIvDISX0gOssEUmVmvIt5CAl5egeuCBzkQHSQzr0JNC3V0sah0Evzz6/zl0OXpDq/BDCEs/4XMynRf9w==)";
    };
  };

  # services.qbittorrent's own ExecStartPre (`install -Dm600 <nix-store
  # conf> <liveConf>`) fully overwrites liveConf on *every* start, not
  # just the first -- confirmed live, twice, this session: anything set
  # through the WebUI that isn't covered by serverConfig (WebUI.APIKey,
  # or WebUI.Username/Password_PBKDF2 for anyone not using
  # extraServerConfig/defaultWebui above) gets silently wiped on the
  # next restart/rebuild. Instead of managing all of that, preserve
  # whatever's already live across the overwrite: capture every WebUI\*
  # line except WebUI\Port (the one WebUI setting serverConfig always
  # manages, via cfg.webuiPort) before install runs, then splice it back
  # into [Preferences] right after install runs. grep -F/sed -i, not a
  # Nix-side parse -- this file's content is arbitrary runtime state Nix
  # never sees.
  captureWebuiSettings = ''
    if [ -f "${liveConf}" ]; then
      ${pkgs.gnugrep}/bin/grep -F 'WebUI\' "${liveConf}" | ${pkgs.gnugrep}/bin/grep -Fv 'WebUI\Port=' > "${webuiBackupFile}" || true
    else
      rm -f "${webuiBackupFile}"
    fi
  '';
  restoreWebuiSettings = pkgs.writeShellScript "qbittorrent-restore-webui-settings" ''
    if [ -s "${webuiBackupFile}" ]; then
      ${pkgs.gnused}/bin/sed -i "/^\[Preferences\]$/r ${webuiBackupFile}" "${liveConf}"
    fi
    rm -f "${webuiBackupFile}"
  '';

  # defaultWebui is the base layer (lowest priority) -- extraServerConfig
  # (config/self-hosted/qbittorrent.nix's own WebUI, once `secrets
  # qbittorrent` generates one) overrides it the instant it sets WebUI
  # itself, same recursiveUpdate right-wins-on-conflict rule as the
  # hardcoded block below already relies on.
  serverConfig = lib.recursiveUpdate defaultWebui (lib.recursiveUpdate cfg.extraServerConfig (
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
  ));

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
        # savePath/tempPath live on config.vars.mountpoints.device.storage.path
        # now too (a /home-rooted mount, moved off the old external
        # /run/media/<user>/Storage), so the same BindPaths grant covers
        # them alongside profileDir -- requireMounts already lists both.
        systemd.services.qbittorrent.wantedBy =
          lib.mkForce (lib.optionals cfg.autoStart [ "multi-user.target" ]);
        systemd.services.qbittorrent.serviceConfig.ProtectHome = lib.mkForce "tmpfs";
        systemd.services.qbittorrent.serviceConfig.BindPaths = cfg.requireMounts;

        # Both gated on cfg.immutable -- see its own description for why
        # (off by default; prefer `secrets qbittorrent` for the
        # password specifically, this is for everything else). Contents
        # are cfg.immutable ? captureWebuiSettings : "", not lib.mkIf
        # captureWebuiSettings -- preStart is types.lines with no
        # default, and mkIf false drops the definition entirely instead
        # of contributing "" (same trap dotfiles.nix's own preStart
        # comment already documents hitting for
        # system.activationScripts). optionalString always yields a
        # real string. ExecStartPre is a plain listOf, no such trap, but
        # mkAfter still matters -- captureWebuiSettings runs as part of
        # this preStart, concatenating onto the requireMounts check
        # mountCheckUnits already adds there, both landing in the same
        # (first) ExecStartPre, ahead of services.qbittorrent's own
        # install step; restoreWebuiSettings has to be a genuinely
        # separate entry (mkAfter, so it lands after both preStart *and*
        # the install step already in this list) -- preStart alone can't
        # express "after install" timing, it's already spoken for as the
        # first entry.
        systemd.services.qbittorrent.preStart =
          lib.optionalString cfg.immutable captureWebuiSettings;
        systemd.services.qbittorrent.serviceConfig.ExecStartPre =
          lib.mkAfter (lib.optionals cfg.immutable [ "${restoreWebuiSettings}" ]);

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
