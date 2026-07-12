{ lib, config, ... }:

# Schema only -- logic lives in ./qbittorrent.nix. Wraps nixpkgs' own
# mature services.qbittorrent module (via
# ../lib/mk-from-native/services.nix, the same helper Immich uses) --
# real, confirmed by reading nixos/modules/services/torrent/qbittorrent.nix
# directly: a dedicated system user, real hardening on every unit,
# typed webuiPort/torrentingPort options, and a real freeform
# serverConfig submodule that maps straight onto qBittorrent.conf.
#
# Not in the original 8-service migration scope (the old
# ~/Scripts/Self-hosted/QBitTorrent/main.sh was a bare nohup+PID-file
# wrapper around the system qbittorrent-nox package, with no real
# per-machine config of its own). But a real prior install's actual
# config *was* found mid-session, on a different mount than the old
# bash framework ever referenced
# (/run/media/herauxvalle/Media/Home/.config/qBittorrent/qBittorrent.conf)
# -- read directly, not guessed, and it's the real source every path/
# port default below is pinned against. Real, substantial pre-existing
# content also already sits on the external Storage drive
# (Torrents/{Library,Incomplete,Database,Deprecated}, 3.5TB in Library/
# alone) -- all four map to real qBittorrent settings (see paths below),
# confirmed matching that same recovered conf file exactly.
{
  imports = [ ./qbittorrent.nix ];

  options.vars.selfHosted.qbittorrent = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Master switch. true = services.qbittorrent.enable wired on, live
        unit exists. false = none of it exists. No teardown mechanism --
        same reasoning as Immich's own default.nix (profileDir/savePath/
        tempPath are all real, potentially-irreplaceable paths with no
        dataDir-shaped structure to scope an automated teardown against).
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the live unit starts automatically on boot/rebuild.
        Unlike this framework's own from-scratch services, this isn't a
        native option on services.qbittorrent -- its own wantedBy =
        [ "multi-user.target" ] is hardcoded in the wrapped module.
        qbittorrent.nix force-overrides it (lib.mkForce) to actually
        honor this flag, same mechanism as Immich's own autoStart.
      '';
    };

    immutable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        services.qbittorrent reinstalls the entire qBittorrent.conf from
        serverConfig on *every* start (not just the first), which
        silently wipes anything set through the WebUI that isn't
        declared in serverConfig -- WebUI.APIKey, or WebUI.Username/
        Password_PBKDF2 for anyone not using extraServerConfig/
        defaultWebui (see extraServerConfig's own comment). true =
        capture whatever WebUI\* is live right before each overwrite and
        splice it back in right after, so it survives restarts. false
        (default) = don't bother; the file just regenerates exactly as
        serverConfig declares it, same as upstream's own behavior.
        Prefer `secrets qbittorrent` (generates a real WebUI login,
        ready to paste into extraServerConfig directly) over turning
        this on just for a password -- that becomes a real Nix-declared
        value that survives restarts on its own, no capture/restore
        needed. This is more for anything else you tweak under Options
        -> Web UI that isn't worth declaring in Nix at all (HTTPS,
        bypass-auth-for-localhost, ...).
      '';
    };

    profileDir = lib.mkOption {
      type = lib.types.str;
      description = ''
        Passed to services.qbittorrent.profileDir -- qBittorrent's own
        internal state (config, session/resume data, GeoDB). No generic
        default (matches Immich's mediaLocation reasoning) -- real value
        is vault-backed (~/Images/SelfHosted/QBitTorrent), not the
        native module's own default (/var/lib/qBittorrent/, a plain
        system location this framework doesn't otherwise touch).
      '';
    };

    webuiPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Passed straight to services.qbittorrent.webuiPort -- a real, already-typed option on the wrapped module (--webui-port). Real value on this machine is 7080 (WebUI\\Port in the recovered real qBittorrent.conf, matches the old main.sh's own claimed port too).";
    };

    host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional bind-address override, mapped to serverConfig's real
        Preferences.WebUI.Address key (confirmed by actually running
        qbittorrent-nox, setting it via its own WebAPI, and reading the
        resulting qBittorrent.conf -- not guessed, and not documented
        anywhere in qBittorrent's own wiki; the recovered real conf
        never set this key at all, so null is also the real prior
        value, not just a safe default).
      '';
    };

    torrentingPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Passed to services.qbittorrent.torrentingPort if set. Real value on this machine is 1729 (Session\\Port in the recovered real qBittorrent.conf).";
    };

    # Grouped together (all four are "a real absolute path qBittorrent
    # writes .torrent-related files to") rather than four flat options,
    # per direct request. Each still maps to a genuinely distinct real
    # BitTorrent.Session.* key -- confirmed for every one of them by
    # actually running qbittorrent-nox, setting it via its own live
    # WebAPI, and reading back the resulting qBittorrent.conf, *and*
    # cross-checked against the real recovered prior config
    # (/run/media/herauxvalle/Media/Home/.config/qBittorrent/qBittorrent.conf)
    # -- every one of the four matched exactly once that file was found,
    # including which of Database/Deprecated is export vs finishedExport
    # (a judgment call before the recovered conf settled it for real).
    paths = {
      save = lib.mkOption {
        type = lib.types.str;
        description = ''
          Completed downloads, mapped to
          serverConfig.BitTorrent.Session.DefaultSavePath. No generic
          default -- real value is the external Storage drive's
          already-existing Torrents/Library/ (3.5TB of real content).
        '';
      };

      temp = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          In-progress/incomplete downloads, mapped to
          serverConfig.BitTorrent.Session.TempPath (+ TempPathEnabled,
          set true automatically whenever this is non-null). null =
          disabled, incomplete downloads land directly in paths.save.
          Real value is Torrents/Incomplete/.
        '';
      };

      export = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Mapped to serverConfig.BitTorrent.Session.TorrentExportDirectory
          -- every added torrent's .torrent file gets copied here,
          unconditionally. null = disabled. Real value is
          Torrents/Database/.
        '';
      };

      finished = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Mapped to
          serverConfig.BitTorrent.Session.FinishedTorrentExportDirectory
          -- a torrent's .torrent file only gets copied here once that
          download finishes. null = disabled. Real value is
          Torrents/Deprecated/.
        '';
      };
    };

    requireMounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths that must already be mountpoints before the live unit starts. Real value needs both the SelfHosted vault (profileDir) and the external Storage drive (every paths.* entry).";
    };

    # Freeform escape hatch onto the wrapped module's own serverConfig,
    # for anything not covered by the typed options above -- same
    # "environment"-style catch-all shape every other service's
    # environment option has, just INI-shaped instead of env-var-shaped
    # since that's what this wrapped module's own real config surface
    # is. Deliberately not routed through a generic field-mapping table
    # (see immich.nix's own reasoning) -- host/paths.* above are each
    # their own real, typed option; this exists for genuinely one-off
    # extras. Real config on this machine ports several more real,
    # non-secret preferences straight from the recovered conf file this
    # way (Session\Encryption, AnonymousModeEnabled, MaxActiveDownloads,
    # QueueingSystemEnabled, IgnoreLimitsOnLAN, MultiConnectionsPerIp,
    # PieceExtentAffinity, SSL\Port, Core\AutoDeleteAddedTorrentFile,
    # MergeTrackersEnabled, General\Locale) rather than a dozen more
    # dedicated typed options for settings this framework has no other
    # reason to treat specially.
    #
    # WebUI\Username/Password_PBKDF2 CAN go here (config/self-hosted/
    # qbittorrent.nix's own WebUI = {...} block does exactly that) --
    # serverConfig always ends up as a pkgs.writeText derivation, so
    # this still lands in the world-readable Nix store and (config/ is
    # git-tracked) this repo's history, same as every other value here.
    # Accepted tradeoff, not a non-issue: it's a PBKDF2 hash, not a
    # plaintext password, and this repo isn't meant to be published as-
    # is. `secrets qbittorrent` generates one (prompts for a
    # username/password, prints a ready-to-paste WebUI = {...} block --
    # see that script's own comment for the algorithm). Until you've run
    # it, qbittorrent.nix's own defaultWebui falls back to a known
    # admin/"changeme" login instead of a random one-session temp
    # password you'd otherwise have to fish out of `journalctl -u
    # qbittorrent` -- change it soon after first start, same as you
    # would any other seeded default credential.
    extraServerConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Merged into services.qbittorrent.serverConfig on top of host/paths.*'s own real mapping (and qbittorrent.nix's own defaultWebui fallback, lowest priority of the three). See this option's own top comment for the WebUI credential story.";
    };
  };
}
