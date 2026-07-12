{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.selfHosted.jellyfin option, all commented
# out. Same shape as glossar/main/variables.nix, scoped to one service.
# Schema: modules/services/self-hosted/jellyfin/default.nix. Real values
# on this machine: config/self-hosted/jellyfin.nix. Full reference
# (systemd units, workflows, "why" for every mechanism below):
# modules/services/self-hosted/jellyfin/info.md.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste reference.
# Copy a block (or a line out of one) into config/self-hosted/jellyfin.nix
# and uncomment it there to actually set it. Terse, ini-style companion to
# that service's info.md -- regenerate by hand alongside it, nothing keeps
# either in sync automatically.
# =========================================================================

{
  # config.vars.selfHosted.jellyfin = {

  #   # --- master switch --------------------------------------------------
  #   # true = live service + actions exist and run. false = torn down
  #   # automatically on the next rebuild (see teardownPaths below), not
  #   # just absent.
  #   enabled = false;

  #   # --- plain base dir -- cache/transcode/log live directly here --------
  #   # config/data/libraries/<name> are all storage-backed symlinks (see storage).
  #   dataDir = "${homeDirectory}/Applications/Networking/Jellyfin";

  #   autoStart = true;  # false = exists, systemctl start-able, but not on boot/rebuild

  #   # --- paired facts about the pinned release -- both required together --
  #   # nix-prefetch-url --type sha256 <url> | nix hash convert --to sri
  #   version = "10.11.11";
  #   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  #   # --- passthrough env for the live process -----------------------------
  #   # DOTNET_GCConserveMemory/DOTNET_EnableDiagnostics are real, confirmed-used.
  #   environment = {
  #     DOTNET_GCConserveMemory = "5";
  #     DOTNET_EnableDiagnostics = "0";
  #   };

  #   # --- optional typed override, pushed via Jellyfin's own REST API (postStart) --
  #   # no env var, no CLI flag exists for this (confirmed: ASPNETCORE_URLS is
  #   # ignored). No `host` option -- Jellyfin's network config has no bind-
  #   # address field at all. null (default) = network.xml's own port applies.
  #   port = null;

  #   # --- vault + external-drive real data -- see info.md's "Real, migrated data" --
  #   storage = [
  #     { src = "config"; dest = "${homeDirectory}/Images/SelfHosted/Jellyfin/config"; }
  #     { src = "data"; dest = "${homeDirectory}/Images/SelfHosted/Jellyfin/data"; }
  #     { src = "libraries/media-movies"; dest = "/run/media/${username}/Storage/Movies"; }
  #   ];

  #   # --- must already be mountpoints before this service (or its preStart) runs --
  #   requireMounts = [
  #     "${homeDirectory}/Images/SelfHosted"
  #     "/run/media/${username}/Storage"
  #   ];

  #   # --- what enabled=false actually removes -------------------------------
  #   # Non-empty on purpose here (unlike most services) -- nested storage
  #   # entries (libraries/<name>) aren't correctly recognized by the default
  #   # "everything but storage" rule. Only the genuinely-disposable scratch dirs.
  #   teardownPaths = [ "cache" "transcode" "log" ];

  #   # --- open-file-descriptor limit (systemd LimitNOFILE) -- large libraries --
  #   fdLimit = 65536;

  #   # --- ffmpeg binary, passed to Jellyfin's own --ffmpeg flag --------------
  #   # null = pkgs.jellyfin-ffmpeg (nixpkgs' own Jellyfin-patched build).
  #   ffmpeg = null;

  #   # --- theme CSS, embedded directly into Jellyfin's branding CustomCss ---
  #   # no separate server, no hostname -- works from any device that can
  #   # already reach Jellyfin at all. See info.md.
  #   theme = {
  #     enable = false;
  #     cssPath = ../../Themes/Jellyfin/ElegantFin/theme.css;
  #   };

  #   # --- third-party repos only -- the official one is already built in ----
  #   # written into Jellyfin's own repositories.xml, only if non-empty.
  #   pluginRepos = [
  #     { name = "My Repo"; url = "https://example.com/manifest.json"; }
  #   ];

  #   # --- installed via Jellyfin's own REST API in postStart -----------------
  #   # find a guid: curl -sL <manifest-url> | jq -r '.[] | select(.name == "X") | .guid'
  #   # real examples, confirmed against the official manifest directly:
  #   plugins = [
  #     { guid = "9c4e63f1-031b-4f25-988b-4f7d78a8b53e"; version = "latest"; } # Bookshelf
  #     { guid = "170a157f-ac6c-437a-abdd-ca9c25cebd39"; version = "latest"; } # Fanart
  #   ];

  # };
}
