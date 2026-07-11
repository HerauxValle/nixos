{ lib, config, ... }:

# Schema only -- logic lives in ./fhs.nix (sandbox + venv install) and
# ./comfyui.nix (wiring), same split as every other module here.
#
# Ported from ~/Scripts/Self-hosted/ComfyUI/, read as a behavioral
# reference only.
{
  imports = [ ./comfyui.nix ];

  options.vars.selfHosted.comfyui = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Master switch for the ComfyUI service.";
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
      description = "Where the Python venv lives -- disposable, regenerable from requirementsLock via the @install action.";
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
      description = "Every node ever pinned via fetchFromGitHub (owner/repo/rev/hash) -- get a new entry's rev+hash with nix-prefetch-git. Only entries listed in installed.nodes actually get symlinked.";
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
      description = "Every model ever pinned. Only entries whose name is listed in installed.models are ever fetched by @sync or kept by @cleanup.";
    };

    # The actually-active subset -- what @sync will fetch and @cleanup
    # will keep. Two flat lists of names/repos rather than moving entries
    # between files: toggling something on/off is a one-line change here
    # instead of relocating a whole pinned block, and the pin itself
    # never has to be re-fetched just to re-enable something.
    installed = {
      nodes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "repo values from nodeStore that should be symlinked into custom_nodes/. Checked against nodeStore at eval time -- an unknown repo here is a hard error, not a silent no-op.";
      };

      models = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "name values from modelStore that @sync should fetch and @cleanup should keep. Checked against modelStore at eval time -- an unknown name here is a hard error, not a silent no-op.";
      };
    };
  };
}
