# &desc: "Jellyfin service config -- enabled/dataDir with cache/transcode/log, config/data/libraries symlinks, version/hash pinning."

{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/jellyfin/. Data only, same as
# ollama.nix/stash.nix.
{
  config.vars.services.selfHosted.jellyfin = {
    # true = installed: systemd unit exists. false = torn down on the
    # next rebuild -- cache/transcode/log removed; config/data/
    # libraries/* (all storage-backed) are never touched by that
    # teardown.
    enabled = true;

    # Plain, always-available -- real writable subdirs Jellyfin itself
    # expects (cache, transcode, log); config/data/libraries/* are
    # symlinks (see storage below).
    dataDir = "${config.vars.identity.homeDirectory}/Applications/Networking/Jellyfin";

    # Off for now -- still exists, still systemctl start-able by hand,
    # just not pulled in on boot/rebuild. Same as every other service on
    # this machine right now.
    autoStart = false;

    # Update together -- see
    # ../../modules/services/self-hosted/jellyfin/default.nix for how to
    # get a new hash when bumping version.
    version = "10.11.11";
    hash = "sha256-n38ZSn43d3z94NEHwIj8R+gceQREAEasDOt6KJVGz3k=";

    environment = {
      DOTNET_GCConserveMemory = "5";
      DOTNET_EnableDiagnostics = "0";
    };

    # null = no override -- network.xml's own InternalHttpPort/
    # PublicHttpPort (8096) apply exactly as they already do. No `host`
    # option exists for Jellyfin at all -- see default.nix's own comment
    # for why (no such field exists in its network config).
    port = null;

    # config/data -> the real Jellyfin database (users, watch history,
    # metadata cache) -- vault-backed, recovered from a backup drive
    # snapshot of the old bash framework's config/ (never vault-backed
    # there either); data/ starts empty, no real backup of it existed.
    # libraries/<name> -> media library roots Jellyfin's own dashboard
    # library definitions point at -- mostly the external Storage drive
    # (fixed from the old, stale /mnt/Storage to the real mount point,
    # /run/media/<user>/Storage, same class of bug already found and
    # fixed for Stash this session), one at the vault's own artwork
    # subdir (moved out from directly under config.vault.jellyfin to
    # avoid colliding with the config/data entries above, which didn't
    # exist as vault entries in the old setup).
    storage = [
      { src = "config"; dest = "${config.vars.identity.homeDirectory}/Images/SelfHosted/Jellyfin/config"; }
      { src = "data"; dest = "${config.vars.identity.homeDirectory}/Images/SelfHosted/Jellyfin/data"; }
      { src = "libraries/media-movies"; dest = "${config.vars.system.mountpoints.device.storage.path}/Movies"; }
      { src = "libraries/media-shows"; dest = "${config.vars.system.mountpoints.device.storage.path}/Shows"; }
      { src = "libraries/media-anime"; dest = "${config.vars.system.mountpoints.device.storage.path}/Anime"; }
      { src = "libraries/media-music"; dest = "${config.vars.system.mountpoints.device.storage.path}/Music"; }
      { src = "libraries/media-audiobooks"; dest = "${config.vars.system.mountpoints.device.storage.path}/Audiobooks"; }
      { src = "libraries/media-books"; dest = "${config.vars.system.mountpoints.device.storage.path}/Books"; }
      { src = "libraries/media-photos"; dest = "${config.vars.system.mountpoints.device.storage.path}/Photos"; }
      { src = "libraries/media-selfhosted"; dest = "${config.vars.identity.homeDirectory}/Images/SelfHosted/Jellyfin/artwork"; }
    ];

    # Both real mounts storage above depends on. Storage is
    # config.vars.system.mountpoints.device.storage.path now
    # (/home/${config.vars.identity.username}/Drives/Storage), not the old
    # udisks2-managed /run/media/<user>/Storage.
    requireMounts = [
      "${config.vars.identity.homeDirectory}/Images/SelfHosted"
      config.vars.system.mountpoints.device.storage.path
    ];

    # Non-empty -- see default.nix's own comment for why (nested storage
    # entries, e.g. libraries/media-movies, aren't correctly recognized
    # by the default "everything but storage" teardown, which only
    # matches top-level basenames). Only the genuinely-disposable scratch
    # dirs, matching the old cleanup.sh's own "safe to clear" reasoning.
    teardownPaths = [ "cache" "transcode" "log" ];

    fdLimit = 65536;

    # null = pkgs.jellyfin-ffmpeg (nixpkgs' own Jellyfin-patched build,
    # with extra hwaccel support stock ffmpeg lacks) -- see jellyfin.nix.
    ffmpeg = null;

    # Real theme -- ElegantFin, a genuinely third-party, actively
    # maintained community theme (not hand-authored). The active build's
    # minified CSS was frozen into Dotfiles/Themes/Jellyfin/ElegantFin/
    # (its own subdirectory, so more theme options can be added later
    # without colliding) rather than referencing ~/Projects/JellyFin/
    # ElegantFin/ directly -- keeps it git-tracked/backed-up like every
    # other themed app in this repo. To pick up a newer ElegantFin build,
    # manually re-copy the file and rebuild -- same workflow as SearXNG's
    # themes. Embedded directly into Jellyfin's own branding CustomCss
    # (see lib/theme-sync.nix) -- no separate server, no hostname, works
    # from any device that can already reach Jellyfin at all.
    theme = {
      enable = true;
      cssPath = ../../../Themes/Jellyfin/ElegantFin/theme.css;
    };

    # Empty -- matches the old JELLYFIN_PLUGIN_REPOS/JELLYFIN_PLUGINS
    # (both declared, zero plugins ever actually active). The mechanism
    # is real and ready; nothing to reconcile until you actually want one.
    pluginRepos = [
      # Only for THIRD-PARTY repos -- the official one is already built
      # into the binary, no entry needed for it.
      # { name = "My Repo"; url = "https://example.com/manifest.json"; }
    ];

    plugins = [
      # How to find a guid: curl the manifest JSON for whichever repo
      # has the plugin (official: https://repo.jellyfin.org/releases/plugin/manifest-stable.json,
      # or your own pluginRepos URL above), then look up the "guid" field
      # by name, e.g.:
      #   curl -sL https://repo.jellyfin.org/releases/plugin/manifest-stable.json \
      #     | jq -r '.[] | select(.name == "Bookshelf") | .guid'
      # Two real examples, confirmed by actually running that command
      # against the official manifest, not guessed:
      # { guid = "9c4e63f1-031b-4f25-988b-4f7d78a8b53e"; version = "latest"; } # Bookshelf
      # { guid = "170a157f-ac6c-437a-abdd-ca9c25cebd39"; version = "latest"; } # Fanart
    ];
  };
}
