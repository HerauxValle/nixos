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
      description = "Environment variables for the live ollama process and the sync unit.";
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
