{ lib, config, ... }:

# Schema only -- logic lives in ./comfyui.nix (wiring) and ./lib/ (the
# implementation-detail pieces comfyui.nix ties together: fhs.nix,
# node-mounting.nix, requirements.nix, models-sync.nix, update.nix).
#
# Ported from ~/Scripts/Self-hosted/ComfyUI/, read as a behavioral
# reference only.
{
  imports = [ ./comfyui.nix ];

  options.vars.selfHosted.comfyui = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Master switch. true = the live service, its actions, and
        preStart/postStart reconciliation all run exactly as declared.
        false = treated as if this service doesn't exist -- no systemd
        units at all, and if it was previously installed, the next
        rebuild automatically tears down exactly what it can safely
        rebuild (venv, mounted nodes, fetched models), never anything
        storage-backed or otherwise outside that reconcilable set. See
        ../docs/architecture.md and self-hosted.nix's
        mkTeardownActivationScript.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.homeDirectory}/Applications/Networking/ComfyUI";
      description = "Plain, always-available path -- holds the venv, model files, and node source symlinks.";
    };

    # Lives under ~/.impure/, not dataDir -- same reasoning as
    # OpenWebUI's venvDir: a venv is real, pip-managed files on disk
    # that Nix cannot fully account for, kept apart from dataDir's
    # declared/backed-up data on purpose.
    venvDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.homeDirectory}/.impure/python-venvs/self-hosted/comfyui";
      description = "Where the Python venv lives -- disposable, regenerated from requirementsLock automatically by preStart's venvEnsureScript whenever the lock's hash changes.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the live service starts automatically on boot/rebuild.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables for the live ComfyUI process.";
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
        storage entry covers" -- only safe when dataDir holds nothing
        else. Non-empty scopes the teardown to exactly these paths
        instead, leaving everything else in dataDir alone regardless of
        storage. ComfyUI's dataDir also holds output/temp/input (real
        generated/uploaded content, no storage entry covers it), so this
        must stay non-empty here.
      '';
    };

    # Paired facts about the exact ComfyUI core commit pinned -- no
    # sensible generic default (there's no "right" revision), both
    # required together, same shape as Ollama's version/hash.
    coreRev = lib.mkOption {
      type = lib.types.str;
      description = "ComfyUI core git rev to pin (comfyanonymous/ComfyUI).";
    };

    coreHash = lib.mkOption {
      type = lib.types.str;
      description = "Nix fetchFromGitHub hash (SRI form) for coreRev.";
    };

    # The full catalog of every node ever pinned, whether or not it's
    # currently active -- not the same as "what gets symlinked", see
    # installed.nodes below. No generic default here (unlike vars.scripts'
    # one "pacnix" entry) -- ComfyUI-Manager is just another node like the
    # rest, not infrastructure for managing this repo itself. `repo` is
    # the addressable key: reference it in installed.nodes to activate it.
    nodeStore = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          owner = lib.mkOption { type = lib.types.str; };
          repo = lib.mkOption { type = lib.types.str; description = "Also the directory name under custom_nodes/, and the addressable key for installed.nodes."; };
          rev = lib.mkOption { type = lib.types.str; };
          hash = lib.mkOption { type = lib.types.str; };
        };
      });
      default = [ ];
      description = "Every node ever pinned via fetchFromGitHub (owner/repo/rev/hash) -- get a new entry's rev+hash with nix-prefetch-git. Only entries listed in installed.nodes actually get bind-mounted.";
    };

    # Real, individual fixes for specific nodes' own source bugs (a bad
    # hardcoded path, a hardcoded font lookup) -- not a generic
    # node-configuration mechanism, and deliberately scoped to ComfyUI
    # only rather than a shared self-hosted.nix concept: no other
    # service has anything resembling "many pluggable third-party
    # source components with occasional per-component bugs" to patch.
    # See config/self-hosted/comfyui/catalog/patches.nix.
    nodePatches = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          repo = lib.mkOption {
            type = lib.types.str;
            description = "nodeStore repo name this patch applies to.";
          };
          script = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = ''
              Shell fragment run against a writable copy of the node's
              fetched source (cwd unset -- use $out) before it's
              bind-mounted in. Empty (the default) means this entry
              exists only for its dirs -- a node needing writable
              directories pre-created but no actual source change
              doesn't need a no-op script to express that.
            '';
          };
          dirs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Extra paths, relative to this node's own writable
              dataDir/node_data/<repo> directory, that must exist
              (possibly empty) before the node's own code runs --
              generates the matching mkdir -p entries in preStart
              automatically. Only needed when a node's own os.mkdir/
              os.listdir call requires an exact nested path to already
              exist rather than creating it recursively itself. The
              base node_data/<repo> directory itself is always created
              regardless of this list, for every entry in nodePatches
              (whether or not it also has a script).
            '';
          };
        };
      });
      default = [ ];
      description = ''
        Per-node fixes -- a source patch (script), pre-created writable
        directories (dirs), or both. script is applied by
        ./lib/node-mounting.nix's mkNodeSrc; dirs generates preStart
        mkdir -p entries, see comfyui.nix. A repo with no entry here is
        used entirely as fetched, no extra directories created.
      '';
    };

    # The full catalog of every model ever pinned -- ~700GB across all of
    # them, deliberately never all installed at once. `name` is the
    # addressable key for installed.models; a handful of entries share a
    # name on purpose (one logical model split across multiple files,
    # e.g. florence2-base's model/config/tokenizer/tokenizer_config).
    modelStore = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Addressable key for installed.models. Not required to be unique -- entries sharing a name are one logical model split across files, and get installed/removed together.";
          };
          type = lib.mkOption {
            type = lib.types.enum [ "hf" "civitai" "git" "url" ];
            description = "Download source.";
          };
          url = lib.mkOption { type = lib.types.str; };
          target = lib.mkOption {
            type = lib.types.str;
            description = "Path, relative to dataDir, the model is saved to.";
          };
        };
      });
      default = [ ];
      description = "Every model ever pinned. Only entries whose name is listed in installed.models are ever fetched, or kept once fetched -- both handled automatically by preStart on every service start.";
    };

    # The actually-active subset -- what preStart bind-mounts/fetches and
    # keeps in sync on every service start. Two flat lists of names/repos
    # rather than moving entries between files: toggling something on/off
    # is a one-line change here instead of relocating a whole pinned
    # block, and the pin itself never has to be re-fetched just to
    # re-enable something.
    installed = {
      nodes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "repo values from nodeStore that should be bind-mounted into custom_nodes/ (see prepareNodeMountsScript). Checked against nodeStore at eval time -- an unknown repo here is a hard error, not a silent no-op.";
      };

      models = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "name values from modelStore that preStart should fetch and keep on disk, removing anything under dataDir/models backing a name not listed here. Checked against modelStore at eval time -- an unknown name here is a hard error, not a silent no-op.";
      };
    };
  };
}
