{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/qbittorrent/. Data only, same as
# every other service's config/self-hosted/<name>.nix.
#
# Every value below is pinned against a real prior install's actual
# config, found mid-session at
# /run/media/herauxvalle/Media/Home/.config/qBittorrent/qBittorrent.conf
# (a different mount than the old bash framework ever referenced) --
# read directly, not guessed or assumed from the old main.sh alone.
{
  config.vars.selfHosted.qbittorrent = {
    enabled = true;

    # Off for now -- still exists, still systemctl start-able by hand,
    # just not pulled in on boot/rebuild. Matches every other migrated
    # service's real config on this machine right now.
    autoStart = false;

    # Vault-backed real internal state (config, session/resume data,
    # GeoDB) -- fresh, no prior profile ever existed at this exact path
    # (the recovered real install lived under a different mount
    # entirely, ~/.config/qBittorrent on the Media drive, not vault-
    # backed at all there).
    profileDir = "${config.vars.homeDirectory}/Images/SelfHosted/QBitTorrent";

    # Real values from the recovered qBittorrent.conf (WebUI\Port=7080,
    # Session\Port=1729) -- not the wrapped module's own defaults
    # (8080, unset).
    webuiPort = 7080;
    torrentingPort = 1729;

    # null -- the recovered conf never set Preferences\WebUI\Address
    # either, so this is the real prior value, not just a safe default.
    host = null;

    # The external Storage drive's already-existing, real torrent
    # library (confirmed by inspecting the drive directly, and every
    # one of these four paths matches the recovered conf's own
    # BitTorrent.Session.* values exactly). Mounted via
    # config.vars.mountpoints (modules/system/mountpoints/) at
    # /home/${config.vars.username}/Drives/Storage now, not the old
    # udisks2-managed /run/media/<user>/Storage -- ProtectHome="tmpfs"+
    # BindPaths below (reusing requireMounts, same proven mechanism as
    # Immich's own /home-rooted mediaLocation) is what grants the
    # dedicated qbittorrent system user access to a /home path, no ACL
    # traversal grant needed (see config/self-hosted/acl-traversal.nix's
    # now-commented-out entry for the old /run/media story).
    paths = {
      save = "${config.vars.mountpoints.device.storage.path}/Torrents/Library";
      temp = "${config.vars.mountpoints.device.storage.path}/Torrents/Incomplete";
      export = "${config.vars.mountpoints.device.storage.path}/Torrents/Database";
      finished = "${config.vars.mountpoints.device.storage.path}/Torrents/Deprecated";
    };

    requireMounts = [
      "${config.vars.homeDirectory}/Images/SelfHosted"
      config.vars.mountpoints.device.storage.path
    ];

    # Real, non-secret preferences ported straight from the recovered
    # conf -- see default.nix's own extraServerConfig comment for why
    # WebUI\Username/Password_PBKDF2/APIKey are deliberately NOT here
    # (real values exist in the recovered conf, but this option always
    # lands in the world-readable Nix store and this repo's git
    # history -- set those through the WebUI itself after first start).
    extraServerConfig = {
      BitTorrent = {
        MergeTrackersEnabled = true;
        Session = {
          AnonymousModeEnabled = true;
          ConnectionSpeed = 100;
          Encryption = 1;
          GlobalUPSpeedLimit = 0;
          IgnoreLimitsOnLAN = true;
          MaxActiveDownloads = 2;
          MultiConnectionsPerIp = true;
          PieceExtentAffinity = true;
          QueueingSystemEnabled = true;
          SSL.Port = 49999;
          StartPaused = false;
        };
      };
      Core.AutoDeleteAddedTorrentFile = "Never";
      Preferences.General.Locale = "en";
    };
  };
}
