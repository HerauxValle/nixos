# &desc: "Jellyfin schema -- enabled/dataDir/autoStart/port/version/hash/storage/requireMounts/fdLimit/ffmpeg/theme/plugins options, imports jellyfin.nix."

{ lib, config, ... }:

# Schema only -- logic lives in ./jellyfin.nix (wiring) and ./lib/
# (package.nix, theme-sync.nix, plugins-sync.nix, network-sync.nix,
# wait-for-api.nix, rescan.nix, update.nix). Ported from
# ~/Scripts/Self-hosted/Jellyfin/, read as a behavioral reference only.
#
# Hardware acceleration (configuration/variables/hwaccel.sh's
# JELLYFIN_HW_ACCEL etc) was confirmed DEAD -- grepped the entire old
# bash tree, never reached a real CLI flag or API call anywhere.
# Jellyfin's real transcode config is self-managed via its own
# encoding.xml/dashboard, never touched by any script. Not ported here as
# a working option -- doing so would fabricate functionality the original
# never had. See info.md for the full story.
#
# `port` below IS real and wired (unlike hwaccel) -- but there is
# deliberately no `host` option for Jellyfin, unlike Ollama/SearXNG.
# Confirmed by inspection (a real recovered network.xml) and by testing
# directly (ASPNETCORE_URLS explicitly ignored on a real run, ".NET's own
# standard override doesn't work here"): Jellyfin's NetworkConfiguration
# has no bind-address field at all -- Kestrel always listens on 0.0.0.0.
# A `host` option here would have nothing real to point at.
{
  imports = [ ./jellyfin.nix ];

  options.vars.services.selfHosted.jellyfin = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Master switch. true = the live service and every action run
        exactly as declared. false = treated as if this service doesn't
        exist -- no systemd units at all, and if it was previously
        installed, the next rebuild automatically tears down exactly
        what teardownPaths declares. See ../docs/architecture.md and
        self-hosted.nix's mkTeardownActivationScript.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.identity.homeDirectory}/Applications/Networking/Jellyfin";
      description = ''
        Plain, always-available path. Real writable subdirs Jellyfin
        itself expects: cache, transcode, log (plain, never precious --
        see teardownPaths). config, data, and every libraries/<name>
        entry are storage-backed (see storage below) -- dataDir itself
        never holds their real content, just the symlinks. jellyfin-web
        (the static web client) is never copied here at all -- served
        straight from the read-only package output via --webdir.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the live service starts automatically on boot/rebuild (wantedBy multi-user.target).";
    };

    # Paired facts about the exact release pinned by ./lib/package.nix --
    # no sensible generic default, both required together. Get a hash
    # with: nix-prefetch-url --type sha256 <url> | nix hash convert --to sri,
    # for https://repo.jellyfin.org/files/server/linux/latest-stable/amd64/jellyfin_<version>-amd64.tar.gz
    version = lib.mkOption {
      type = lib.types.str;
      description = "Jellyfin release version to pin, e.g. \"10.11.11\". Must match hash below.";
    };

    hash = lib.mkOption {
      type = lib.types.str;
      description = "sha256 (SRI form) of that version's linux amd64 release tarball.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Environment variables for the live jellyfin process. DOTNET_*
        tuning (DOTNET_GCConserveMemory, DOTNET_EnableDiagnostics) is
        real, confirmed-used behavior ported from the old launch.sh --
        set these here if you want them, nothing is assumed by default.
        JELLYFIN_LOG_LEVEL was declared there too but confirmed dead
        (grepped -- never read by anything), not implied to do anything
        if you set it.
      '';
    };

    # Optional, typed override -- null (the default) means "don't touch
    # anything," network.xml's own InternalHttpPort/PublicHttpPort apply
    # exactly as they already do (real values inside the vault-protected
    # config -- see storage below). Unlike Ollama/SearXNG, this is
    # neither an env var nor a CLI flag -- Jellyfin has no such mechanism
    # for its network config (confirmed: ASPNETCORE_URLS is explicitly
    # ignored on a real run). The only real way to change it is through
    # Jellyfin's own REST API (the same one its dashboard's Networking
    # page uses), which needs the live process up and an admin key --
    # see ./lib/network-sync.nix. Practical consequence: on a genuinely
    # fresh install (no admin key exists yet), this can't take effect
    # until after the setup wizard is completed once -- a real asymmetry
    # against Ollama/SearXNG, which apply from the very first start.
    # There is no `host` option here at all -- see this file's own top
    # comment for why (no such field exists in Jellyfin's network config).
    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Pushed to Jellyfin's own network config (InternalHttpPort + PublicHttpPort) via its REST API in postStart, if set. Requires a restart after the push actually takes effect (Kestrel binds at startup, a config change alone doesn't rebind a live listener). null = network.xml's own value applies, untouched.";
    };

    storage = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          src = lib.mkOption {
            type = lib.types.str;
            description = "Path, relative to dataDir, that should be a symlink.";
          };
          dest = lib.mkOption {
            type = lib.types.str;
            description = "Absolute target the symlink points at.";
          };
        };
      });
      default = [ ];
      description = ''
        Storage relocations, applied as systemd.tmpfiles.rules. Real
        config here covers two different kinds of real data behind the
        same mechanism: Jellyfin's own database (config/, data/ -- vault-
        backed) and media library roots (libraries/<name> -- symlinks
        Jellyfin's own dashboard library definitions point at, most
        pointing at the external Storage drive, one at the vault's own
        artwork subdir). See info.md for the full real list.
      '';
    };

    requireMounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths that must already be mountpoints before this service (or any of its preStart) runs. See modules/services/self-hosted/self-hosted.nix's mkSelfHostedService.";
    };

    teardownPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Paths, relative to dataDir, removed when enabled is set to false
        (see self-hosted.nix's mkTeardownActivationScript). Non-empty
        here on purpose (ComfyUI's shape, not Ollama's) -- dataDir holds
        real storage-backed nested paths (libraries/<name>) the default
        "everything but storage" rule can't correctly recognize (it only
        matches storage entries by their top-level basename under
        dataDir, not nested ones) -- see mkTeardownActivationScript's own
        comment. Real value here is exactly the genuinely-disposable
        scratch space: cache, transcode, log (matches the old
        cleanup.sh's own "safe to clear" reasoning) -- config, data, and
        every libraries/<name> entry are never touched by this.
      '';
    };

    fdLimit = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 65536;
      description = ''
        Open-file-descriptor limit for the live process (systemd
        LimitNOFILE) -- real, confirmed-used behavior ported from the old
        runtime.sh's `ulimit -n "$JELLYFIN_FD_LIMIT"`, useful for large
        media libraries. null = don't set (systemd's own default).
      '';
    };

    ffmpeg = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Package providing bin/ffmpeg, passed to Jellyfin's own --ffmpeg
        flag. Deliberately not "system ffmpeg on PATH" (the old
        deps.sh's approach) -- an explicit Nix path is more robust and
        matches how every other exec path in this framework works.
        Defaults to pkgs.jellyfin-ffmpeg (nixpkgs' own Jellyfin-patched
        build, with extra hwaccel support stock ffmpeg lacks) in
        jellyfin.nix, not here (this file has no pkgs).
      '';
    };

    # Real, hand-crafted-elsewhere theme CSS injected directly into
    # Jellyfin's own branding CustomCss field via its REST API (see
    # ./lib/theme-sync.nix) -- SearXNG's native /preferences-based theme
    # switching has no Jellyfin equivalent, so pushing this via the API is
    # real, necessary machinery, not over-engineering.
    #
    # Embedded, not served from a separate sidecar unit + @import URL --
    # that was the first design here, reverted once it turned out to
    # need a resolvable hostname (jellyfin.local via mDNS) that doesn't
    # exist yet as real infrastructure on this machine. CustomCss is
    # served as part of Jellyfin's own response to every client, so
    # embedding works from any device that can already reach Jellyfin at
    # all -- LAN, VPN, remote, no DNS/mDNS dependency whatsoever. cssPath
    # is a plain file path now (not a directory like SearXNG's themes) --
    # nothing serves it, ./lib/theme-sync.nix just reads its content
    # directly.
    theme = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Master switch for the theme sync. false = skip entirely, same as the old JELLYFIN_THEME_ENABLED=false.";
      };

      cssPath = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Nix path to the real theme.css file. Its content is embedded directly into Jellyfin's branding CustomCss (marker-delimited, so any other manual CSS added via the dashboard survives). null = nothing to sync even if enable = true.";
      };
    };

    # Real, but currently empty -- matches the old JELLYFIN_PLUGIN_REPOS/
    # JELLYFIN_PLUGINS shape (both declared, zero plugins actually
    # active). Reconciled by ./lib/plugins-sync.nix, same postStart pass
    # as the theme sync (both need the live API + an admin key -- see
    # info.md's "port: API push" section, same requirement applies here).
    #
    # You almost never need to add anything here at all: the official
    # Jellyfin plugin repository is already built into the binary itself
    # (confirmed in the old plugins.sh's own comment: "already built-in
    # -- listed here for explicitness") -- pluginRepos is only for
    # THIRD-PARTY repositories beyond that one. Example, to add one:
    #   pluginRepos = [
    #     { name = "My Repo"; url = "https://example.com/manifest.json"; }
    #   ];
    pluginRepos = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          url = lib.mkOption { type = lib.types.str; description = "Manifest JSON URL."; };
        };
      });
      default = [ ];
      description = "Third-party plugin repositories (beyond the official one, already built in), written into Jellyfin's own repositories.xml every start (preStart, pure filesystem -- no live process needed for this part).";
    };

    # To add a plugin: find its `guid` in whichever repo's manifest JSON
    # holds it -- the official one is
    # https://repo.jellyfin.org/releases/plugin/manifest-stable.json,
    # a JSON array of `{ name, guid, versions: [...], ... }` objects (curl
    # it and grep/jq for the plugin's name to find its guid; a
    # third-party repo you added via pluginRepos above works the same
    # way, just a different URL). Real examples from the official
    # manifest, confirmed by fetching it directly (not guessed):
    #   plugins = [
    #     { guid = "9c4e63f1-031b-4f25-988b-4f7d78a8b53e"; version = "latest"; } # Bookshelf
    #     { guid = "170a157f-ac6c-437a-abdd-ca9c25cebd39"; version = "latest"; } # Fanart
    #   ];
    # `version` defaults to "latest" (no ?version= query param sent at
    # all in that case, matching the old plugins.sh's own behavior --
    # Jellyfin installs whatever the manifest offers as current). Set a
    # specific version string (as it appears in that plugin's manifest
    # entry's `versions[].version` field) to pin one instead.
    plugins = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          guid = lib.mkOption { type = lib.types.str; description = "From the repository manifest JSON."; };
          version = lib.mkOption { type = lib.types.str; default = "latest"; };
        };
      });
      default = [ ];
      description = "Declared plugins -- installed via Jellyfin's own REST API in postStart (live process required), once an admin API key exists. Nothing removes an undeclared-but-installed plugin automatically (unlike ComfyUI's nodes/models) -- Jellyfin's own plugin uninstall isn't a simple file deletion, not safe to automate blind.";
    };
  };
}
