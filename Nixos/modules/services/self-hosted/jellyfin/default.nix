{ lib, config, ... }:

# Schema only -- logic lives in ./jellyfin.nix (wiring) and ./lib/
# (package.nix, theme-server.nix, reconcile.nix, update.nix). Ported from
# ~/Scripts/Self-hosted/Jellyfin/, read as a behavioral reference only.
#
# Two things declared in the old configuration/variables/{hwaccel,network}.sh
# were confirmed DEAD -- grepped the entire old bash tree, neither ever
# reached a real CLI flag or API call anywhere: hardware-acceleration
# variables (JELLYFIN_HW_ACCEL etc -- Jellyfin's real transcode config is
# self-managed via its own encoding.xml/dashboard, never touched by any
# script) and JELLYFIN_BIND_ADDRESS/JELLYFIN_HTTP_PORT/JELLYFIN_HTTPS_PORT
# (the real port/bind address Jellyfin actually used, confirmed from a
# recovered real network.xml, was its own default 8096 -- the "6050"
# declared in network.sh was never wired to anything). Neither is ported
# here as a working option -- doing so would fabricate functionality the
# original never had. See info.md for the full story.
{
  imports = [ ./jellyfin.nix ];

  options.vars.selfHosted.jellyfin = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Master switch. true = the live service, the theme server (if
        themeServer.enable), and every action run exactly as declared.
        false = treated as if this service doesn't exist -- no systemd
        units at all, and if it was previously installed, the next
        rebuild automatically tears down exactly what teardownPaths
        declares. See ../docs/architecture.md and self-hosted.nix's
        mkTeardownActivationScript.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.homeDirectory}/Applications/Networking/Jellyfin";
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
    # active). Reconciled by ./lib/reconcile.nix, same postStart pass as
    # the theme sync (both need the live API).
    pluginRepos = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          url = lib.mkOption { type = lib.types.str; description = "Manifest JSON URL."; };
        };
      });
      default = [ ];
      description = "Plugin repositories written into Jellyfin's own repositories.xml every start (preStart, pure filesystem -- no live process needed for this part).";
    };

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
