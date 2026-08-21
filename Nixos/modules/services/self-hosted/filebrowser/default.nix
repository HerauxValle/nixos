# &desc: "FileBrowser schema -- enabled/dataDir/autoStart/host/port/version/hash/storage/requireMounts options, imports filebrowser.nix."

{ lib, config, ... }:

# Schema only -- logic lives in ./filebrowser.nix, imported below, same
# split every other module in this repo uses.
#
# Ported from ~/Scripts/Self-hosted/FileBrowser/, read as a behavioral
# reference only. The simplest service in this tree: a single static
# binary, a single BoltDB file, no venv, no reconciliation list, no
# external services.
{
  imports = [ ./filebrowser.nix ];

  options.vars.services.selfHosted.filebrowser = {
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
      default = "${config.vars.identity.homeDirectory}/Applications/Networking/FileBrowser";
      description = "Plain base dir -- holds nothing on its own, it's just where storage's symlink lands. The BoltDB (users, settings) is the one real data location, see storage below. The binary itself comes from the Nix-built package and never touches this directory.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the live service starts automatically on boot/rebuild (wantedBy multi-user.target). false = it still exists and can be started by hand (systemctl start self-hosted-filebrowser), just never pulled in on its own.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address, passed as --address on every start (and baked into the BoltDB via `config init`/`config set` the first time it's created).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "Bind port, passed as --port on every start (and baked into the BoltDB the first time it's created).";
    };

    root = lib.mkOption {
      type = lib.types.str;
      default = config.vars.identity.homeDirectory;
      description = ''
        Filesystem root FileBrowser serves (--root, applied once via
        `config init` when the BoltDB doesn't exist yet -- ported
        faithfully from the original FB_ROOT="$HOME", not scoped down: the
        original setup deliberately browsed the whole home directory, not
        a subset. Changing this after the database already exists has no
        effect -- `config set --root` would be needed by hand.
      '';
    };

    # Paired facts about the exact release pinned by ./lib/package.nix --
    # no sensible generic default (there's no "right" version), both
    # required together. Get a hash with: nix-prefetch-url --type sha256
    # <url> | then `nix hash convert --to sri`, for
    # https://github.com/filebrowser/filebrowser/releases/download/v<version>/linux-amd64-filebrowser.tar.gz
    version = lib.mkOption {
      type = lib.types.str;
      description = "FileBrowser release version to pin, e.g. \"2.63.18\". Must match hash below.";
    };

    hash = lib.mkOption {
      type = lib.types.str;
      description = "sha256 (SRI form) of that version's linux-amd64-filebrowser.tar.gz release asset.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables for the live filebrowser process.";
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

    # Plain data, set directly in config/self-hosted/filebrowser.nix -- not
    # derived from storage here or anywhere else, same reasoning as
    # ollama/stash's requireMounts.
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
        but the storage symlink itself.
      '';
    };
  };
}
