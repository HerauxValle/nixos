{ lib, config, ... }:

# Schema only -- logic lives in ./fhs.nix (the sandbox + venv install) and
# ./openwebui.nix (wiring), same split as every other module here.
#
# Ported from ~/Scripts/Self-hosted/OpenWebUI/, read as a behavioral
# reference only. Deliberately NOT carried over:
# configuration/hooks/obsidian-unlock.sh, which unlocks a vault literally
# named "Vaults" (~/Images/Vaults.img) -- doesn't match where this
# service's actual data lives (OWUI_STORAGE always pointed at the
# SelfHosted vault, same one Stash uses), confirmed stale/irrelevant, not
# a real dependency.
{
  imports = [ ./openwebui.nix ];

  options.vars.services.selfHosted.openwebui = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Master switch. true = the live service and its actions run
        exactly as declared. false = treated as if this service doesn't
        exist -- no systemd units at all, and if it was previously
        installed, the next rebuild automatically tears down the venv
        and dataDir (minus any storage entries). See
        ../docs/architecture.md and self-hosted.nix's
        mkTeardownActivationScript.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.identity.homeDirectory}/Applications/Networking/OpenWebUI";
      description = "Plain, always-available path -- holds nothing on its own except the venv and the storage symlink below.";
    };

    # Entirely disposable -- fully regenerated from requirementsLock
    # automatically by preStart's venvEnsureScript whenever the lock's
    # hash changes, never a Nix store path (pip needs write access, the
    # store is read-only by design). Lives under
    # ~/.impure/, not dataDir -- a venv is exactly the kind of thing
    # that directory name exists to call out: real files on disk that
    # Nix did not put there and cannot fully account for, kept apart
    # from dataDir's declared/backed-up data.
    venvDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.identity.homeDirectory}/.impure/python-venvs/self-hosted/openwebui";
      description = "Where the Python venv lives.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the live service starts automatically on boot/rebuild.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address, passed as --host.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Bind port, passed as --port.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables for the live open-webui process.";
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

    requireMounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths that must already be mountpoints before this service (or any of its preStart) runs.";
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
