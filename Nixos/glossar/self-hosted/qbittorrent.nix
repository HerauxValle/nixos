{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.services.selfHosted.qbittorrent option, all
# commented out. Same shape as glossar/main/variables.nix, scoped to one
# service. Schema: modules/services/self-hosted/qbittorrent/default.nix.
# Real values on this machine: config/self-hosted/qbittorrent.nix. Full
# reference: modules/services/self-hosted/qbittorrent/info.md.
#
# Wraps nixpkgs' own services.qbittorrent (same mkFromNativeService
# helper Immich uses) -- no dataDir/storage list here, real paths are
# each their own typed option instead (profileDir + the paths.* group).
#
# NOT imported anywhere -- never evaluated, purely a copy-paste
# reference. Copy a block (or a line out of one) into
# config/self-hosted/qbittorrent.nix and uncomment it there to actually
# set it.
# =========================================================================

{
  # config.vars.services.selfHosted.qbittorrent = {

  #   # --- master switch --------------------------------------------------
  #   enabled = false;

  #   autoStart = true;  # false = exists, systemctl start-able, but not on boot/rebuild

  #   # --- internal app state (config, session/resume data, GeoDB) ---------
  #   profileDir = "${homeDirectory}/Images/SelfHosted/QBitTorrent";

  #   # --- real, already-typed options on the wrapped module ----------------
  #   webuiPort = 7080;
  #   torrentingPort = 1729;

  #   # --- optional WebUI bind-address override -----------------------------
  #   # confirmed real via a live instance's own generated qBittorrent.conf
  #   # (Preferences.WebUI.Address) -- not documented anywhere upstream.
  #   # null = qBittorrent's own default (binds every interface).
  #   host = null;

  #   # --- real paths, grouped -- each maps to a distinct BitTorrent.Session.* key --
  #   paths = {
  #     save = "/run/media/${username}/Storage/Torrents/Library";       # completed downloads
  #     temp = "/run/media/${username}/Storage/Torrents/Incomplete";    # null = disabled
  #     export = "/run/media/${username}/Storage/Torrents/Database";    # every added torrent's .torrent file
  #     finished = "/run/media/${username}/Storage/Torrents/Deprecated"; # only once that download finishes
  #   };

  #   # --- must already be mountpoints before the live unit starts ----------
  #   requireMounts = [
  #     "${homeDirectory}/Images/SelfHosted"
  #     "/run/media/${username}/Storage"
  #   ];

  #   # --- freeform escape hatch onto the wrapped module's own serverConfig --
  #   # never put WebUI credentials here -- see default.nix's own comment.
  #   extraServerConfig = {
  #     Preferences.General.Locale = "en";
  #   };

  # };
}
