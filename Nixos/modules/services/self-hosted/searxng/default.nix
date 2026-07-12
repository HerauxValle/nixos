{ lib, config, ... }:

# Schema only -- logic lives in ./searxng.nix (wiring) and ./lib/
# (fhs.nix, update.nix). Ported from ~/Scripts/Self-hosted/SearXNG/, read
# as a behavioral reference only.
#
# Real shape difference from OpenWebUI/ComfyUI: SearXNG has no pip
# package at all (confirmed in the old toolchain.sh's own comment,
# "SearXNG has no pip package -- installed from git") -- upstream is only
# ever installed from a git checkout. Unlike ComfyUI's core (an immutable
# fetchFromGitHub store path, needed there because custom_nodes/ needs a
# real bind-mount trick to stay writable per-node), SearXNG's core has no
# such requirement -- nothing downstream needs it writable except the
# theme symlinks (see themes below), so it's a plain writable git clone
# under srcDir, checked out to coreRev by preStart every start (a no-op
# once already there) -- same "impure, but declared and pinned" shape as
# the venv itself, just one directory over. No coreHash option as a
# result -- there's nothing to fetchFromGitHub-verify against, only a rev
# to check out.
{
  imports = [ ./searxng.nix ];

  options.vars.selfHosted.searxng = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Master switch. true = the live service and its actions run
        exactly as declared. false = treated as if this service doesn't
        exist -- no systemd units at all, and if it was previously
        installed, the next rebuild automatically tears down dataDir
        (minus any storage entries). See ../docs/architecture.md and
        self-hosted.nix's mkTeardownActivationScript.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.homeDirectory}/Applications/Networking/SearXNG";
      description = "Plain, always-available path -- holds nothing but the settings.yml symlink (see storage below, the one real data location).";
    };

    # Real, typed option rather than folded into environment -- SearXNG
    # itself structurally consumes this (searx/settings_defaults.py's
    # SettingsValue(environ_name="SEARXNG_SECRET"), confirmed by reading
    # that file directly): if SEARXNG_SECRET is set, it unconditionally
    # overrides whatever's in settings.yml's server.secret_key, no matter
    # what that value is. Nix's job is exporting this one env var;
    # everything else about server config stays inside the real
    # settings.yml, untouched.
    secret = lib.mkOption {
      type = lib.types.str;
      description = "Session-signing secret, exported as SEARXNG_SECRET on every start -- overrides settings.yml's own server.secret_key.";
    };

    # Both live under ~/.impure/, not dataDir -- same reasoning as every
    # other venv-based service: real, pip/git-managed files on disk Nix
    # cannot fully account for, kept apart from dataDir's declared data
    # on purpose. srcDir is a sibling of venvDir rather than nested
    # inside it deliberately -- mkVenvInstallScript wipes venvDir
    # entirely on every lock-hash change, which would force a needless
    # git-reclone every time if srcDir lived inside it.
    venvDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.homeDirectory}/.impure/python-venvs/self-hosted/searxng";
      description = "Where the Python venv lives -- disposable, regenerated from requirementsLock automatically by preStart's venvEnsureScript whenever the lock's hash changes.";
    };

    srcDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.homeDirectory}/.impure/python-venvs/self-hosted/searxng-src";
      description = "Where the searxng/searxng git checkout lives, pinned to coreRev by preStart every start (a no-op once already at that rev). Kept writable (unlike ComfyUI's core) so theme symlinks can be written directly into searx/templates/, searx/static/themes/.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the live service starts automatically on boot/rebuild (wantedBy multi-user.target).";
    };

    # Optional, typed overrides -- null (the default for both) means
    # "don't touch anything," settings.yml's own server.bind_address/
    # server.port apply exactly as they already do (real values inside
    # the vault-protected file, untouched by this port -- see storage
    # below). This is the *cleanest* of the three host/port mechanisms in
    # this repo (Ollama's rebuilds a combined string, Jellyfin's has no
    # real "host" concept and needs a live API call for port) -- SearXNG
    # has genuine, native, independent env var overrides for exactly
    # these two settings (searx/settings_defaults.py:
    # SettingsValue(..., 'SEARXNG_BIND_ADDRESS') /
    # SettingsValue(..., 'SEARXNG_PORT'), same mechanism `secret` above
    # already uses for SEARXNG_SECRET, confirmed by reading that file
    # directly). Setting either one just adds that env var -- no file
    # patching, no API call, no parsing an existing combined value.
    host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Exported as SEARXNG_BIND_ADDRESS if set -- overrides settings.yml's server.bind_address. null = settings.yml's own value applies.";
    };

    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Exported as SEARXNG_PORT if set -- overrides settings.yml's server.port. null = settings.yml's own value applies.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables for the live SearXNG process.";
    };

    storage = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          src = lib.mkOption {
            type = lib.types.str;
            description = "Path, relative to dataDir, that should be a symlink. Can point at a single file, not just a directory -- L+ tmpfiles rules don't care which.";
          };
          dest = lib.mkOption {
            type = lib.types.str;
            description = "Absolute target the symlink points at.";
          };
        };
      });
      default = [ ];
      description = ''
        Storage relocations, applied as systemd.tmpfiles.rules. SearXNG's
        real config value here is deliberately a single-file entry --
        dataDir/settings.yml -> the real, hand-customized settings.yml in
        the vault -- not a directory. Nix never parses or patches that
        file's contents (no default_theme/host/port options exist here
        as a result -- they're already real values inside that file);
        this is the only place a real filesystem path outside Dotfiles/
        is ever referenced.
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
        (see self-hosted.nix's mkTeardownActivationScript). Empty (the
        default) means "everything directly under dataDir except what a
        storage entry covers" -- safe here since dataDir holds nothing
        but the settings.yml symlink itself.
      '';
    };

    # No sensible generic default (there's no "right" revision) -- see
    # this file's own top comment for why there's no coreHash alongside
    # it, unlike Ollama/Stash's version+hash or ComfyUI's coreRev+coreHash.
    coreRev = lib.mkOption {
      type = lib.types.str;
      description = "searxng/searxng git rev to pin. preStart clones srcDir if missing, then checks out this rev every start (no-op if already there).";
    };

    # Real, hand-crafted theme sources -- each entry gets symlinked into
    # srcDir's searx/templates/<name> and searx/static/themes/<name> by
    # preStart, same mechanism as the old links.sh. Only two real entries
    # exist right now (simple, adversarial) -- a typed list rather than a
    # store/installed split (unlike ComfyUI's nodeStore/installed.nodes):
    # every theme here always gets linked, there's no "declared but not
    # currently wanted" catalog problem to solve, so that extra split
    # would be generalizing for a case that doesn't exist yet.
    themes = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Theme name -- becomes the directory name under searx/templates/ and searx/static/themes/, and a valid value for settings.yml's ui.default_theme.";
          };
          path = lib.mkOption {
            type = lib.types.path;
            description = "Nix path to this theme's source directory (Dotfiles/Themes/Searxng/<name>/, same top-level convention as every other themed app in this repo), containing templates/ and/or static/ subdirs.";
          };
        };
      });
      default = [ ];
      description = "Custom theme sources to symlink into the live SearXNG checkout on every start. See ../docs and links.sh's original behavior in the ported bash reference.";
    };
  };
}
