{ lib, config, ... }:

# Schema only -- logic lives in ./stash.nix, imported below, same split as
# every other module in this repo (and ../ollama/).
#
# Ported from ~/Scripts/Self-hosted/Stash/, read as a behavioral reference
# only. Deliberately NOT carried over: the old runtime.sh's post-start
# autotag/filemonitor GraphQL calls (Old/autotag.py is itself flagged
# "Old" in that tree -- legacy, not current desired behavior) and its
# auto-launch of an Electron webapp (WEBAPP_PATH) -- launching a GUI app
# from a system service that has no display/session access doesn't work
# and doesn't belong here; that was really a desktop convenience for
# running main.sh --start interactively, not core service behavior. If
# any of that turns out to still be wanted, it fits cleanly later as a
# manual mkActionService action, same as Ollama's sync.
{
  imports = [ ./stash.nix ];

  options.vars.selfHosted.stash = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Master switch for the Stash service.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.homeDirectory}/Images/SelfHosted/Stash";
      description = "Stash-managed data: config.yml, database, generated thumbnails/previews, cache, blobs. The binary itself comes from the Nix-built package and never touches this directory.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the live service starts automatically on boot/rebuild (wantedBy multi-user.target).";
    };

    # host/port are real typed options, not environment passthrough --
    # unlike Ollama's OLLAMA_HOST, Stash takes these as CLI flags
    # (`stash --host ... --port ...`), so Nix logic (ollama.nix's
    # execStart) actually has to consume them structurally to build the
    # command line, not just hand them to the process verbatim.
    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address, passed as --host.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9999;
      description = "Bind port, passed as --port.";
    };

    # Paired facts about the exact release pinned by ./package.nix -- see
    # ../ollama/default.nix for how to get a new hash when bumping version.
    version = lib.mkOption {
      type = lib.types.str;
      description = "Stash release version to pin, e.g. \"0.31.1\". Must match hash below.";
    };

    hash = lib.mkOption {
      type = lib.types.str;
      description = "sha256 (SRI form) of that version's stash-linux release asset.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables for the live stash process.";
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

    # Plain data, set directly in config/self-hosted/stash.nix -- not
    # derived from storage here or anywhere else. They happen to agree
    # (this vault is also where a storage entry points) because you wrote
    # them to agree, not because one is computed from the other -- a
    # future service can need a mount check for a reason that has
    # nothing to do with its storage list, or need none at all.
    requireMounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths that must already be mountpoints before this service (or any of its preStart) runs. See modules/services/self-hosted/self-hosted.nix's mkSelfHostedService.";
    };
  };
}
