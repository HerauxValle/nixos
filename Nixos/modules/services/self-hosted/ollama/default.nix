{ lib, config, ... }:

# Schema only -- logic lives in ./ollama.nix, imported below, same split
# every other module in this repo uses (see modules/backup/dotfiles,
# modules/hyprland/plugins, modules/packages/scripts,
# modules/security/sudo-keyfile).
{
  imports = [ ./ollama.nix ];

  options.vars.selfHosted.ollama = {
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
      default = "${config.vars.homeDirectory}/Applications/Networking/Ollama";
      description = "Where pulled model blobs live. Drives OLLAMA_MODELS and storage -- the ollama binary itself comes from the Nix-built package and never touches this directory.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the live service starts automatically on boot/rebuild (wantedBy multi-user.target). false = it still exists and can be started by hand (systemctl start self-hosted-ollama), just never pulled in on its own.";
    };

    # Paired facts about the exact release pinned by ./package.nix -- no
    # sensible generic default (there's no "right" version), both required
    # together. Get a hash with: nix-prefetch-url --type sha256 <url> |
    # then `nix hash convert --to sri`, for
    # https://github.com/ollama/ollama/releases/download/v<version>/ollama-linux-amd64.tar.zst
    version = lib.mkOption {
      type = lib.types.str;
      description = "Ollama release version to pin, e.g. \"0.31.2\". Must match hash below.";
    };

    hash = lib.mkOption {
      type = lib.types.str;
      description = "sha256 (SRI form) of that version's ollama-linux-amd64.tar.zst release asset.";
    };

    # Plain passthrough, same shape as the old bash OLLAMA_ENV array: add
    # a key, it gets exported to the live process and the sync unit
    # verbatim (e.g. OLLAMA_HOST, OLLAMA_CONTEXT_LENGTH, OLLAMA_KEEP_ALIVE,
    # CUDA_VISIBLE_DEVICES). None of these carry Nix-side meaning beyond
    # "set this env var" -- unlike dataDir/models/storage below, which
    # actually drive real logic (tmpfiles rules, the sync script), so
    # giving each one its own typed option would just be restating the
    # same key=value pair as Nix syntax for no benefit.
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables for the live ollama process and the sync unit. OLLAMA_HOST can be set here directly (the plain passthrough way) -- host/port below are an optional, typed override on top, see their own descriptions.";
    };

    # Optional, typed override on top of environment.OLLAMA_HOST -- not a
    # replacement for it. Ollama already reads OLLAMA_HOST as a real env
    # var (host:port combined in one string), so the plain passthrough
    # above already works on its own; these two exist only so host/port
    # can be set as their own typed values (matching Stash/OpenWebUI/
    # FileBrowser's shape) without hand-assembling the combined string
    # yourself. null (the default for both) = no override, whatever's in
    # environment.OLLAMA_HOST (or Ollama's own built-in default) applies
    # exactly as before -- nothing changes unless you set one of these.
    # If either is set, ollama.nix constructs a fresh OLLAMA_HOST from
    # them and it wins over environment.OLLAMA_HOST (last-merged, see
    # ollama.nix), using "0.0.0.0"/"11434" for whichever half you didn't
    # also set.
    host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Bind address override -- if set (with or without port), wins over environment.OLLAMA_HOST.";
    };

    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Bind port override -- if set (with or without host), wins over environment.OLLAMA_HOST.";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Declared models. Reconciled (pulled if missing, removed if installed-but-undeclared) automatically every time the service starts, via postStart -- never during rebuild/activation itself, only once the live server is actually up. See ./sync.nix.";
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
      description = "Storage relocations, applied as systemd.tmpfiles.rules.";
    };

    teardownPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Paths, relative to dataDir, removed when enabled is set to false
        (see self-hosted.nix's mkTeardownActivationScript). Empty (the
        default) means "everything directly under dataDir except what a
        storage entry covers" -- safe here since dataDir holds nothing
        but pulled model blobs.
      '';
    };
  };
}
