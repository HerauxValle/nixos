# &desc: "ComfyUI service wiring -- ties together FHS venv, nodes/models, core pinning, preStart reconciliation, update actions."

{ config, lib, pkgs, ... }:

# Wiring -- the FHS sandbox is ./lib/fhs.nix, the generic systemd/venv
# plumbing is ../self-hosted.nix, node mounting is ./lib/node-mounting.nix,
# the hash-locked venv's requirements.in + install script is
# ./lib/requirements.nix, model fetch/reconciliation is
# ./lib/models-sync.nix, update actions are ./lib/update.nix. This file
# ties all of that to ComfyUI's own values: pinned core source, custom
# nodes, models.
#
# Ported from ~/Scripts/Self-hosted/ComfyUI/, read as a behavioral
# reference only.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.services.selfHosted.comfyui;

  # The actually-active subsets -- everything below (node mounting,
  # requirements.in generation, model sync) operates on these, never on
  # the full nodeStore/modelStore catalogs directly. Filtering here, once,
  # means every consumer downstream automatically respects
  # installed.nodes/installed.models without re-deriving the same filter.
  activeNodes = builtins.filter (n: builtins.elem n.repo cfg.installed.nodes) cfg.nodeStore;
  activeModels = builtins.filter (m: builtins.elem m.name cfg.installed.models) cfg.modelStore;

  # Only patches for currently-installed nodes matter -- a patch entry
  # for a node not in installed.nodes isn't mounted at all, nothing to
  # pre-create a directory for. Every entry gets its own node_data/<repo>
  # base dir regardless of whether it declares any extra `dirs`, since
  # every patched-or-dirs-only entry writes *something* there.
  activeNodePatches = builtins.filter (p: builtins.elem p.repo cfg.installed.nodes) cfg.nodePatches;

  nodeDataDirs = lib.concatMap
    (p: [ "${cfg.dataDir}/node_data/${p.repo}" ]
      ++ map (dir: "${cfg.dataDir}/node_data/${p.repo}/${dir}") p.dirs)
    activeNodePatches;

  nodeDataMkdirScript =
    lib.optionalString (nodeDataDirs != [ ])
      "mkdir -p ${lib.concatStringsSep " " nodeDataDirs}";

  comfyCore = pkgs.fetchFromGitHub {
    owner = "comfyanonymous";
    repo = "ComfyUI";
    rev = cfg.coreRev;
    hash = cfg.coreHash;
  };

  inherit (import ./lib/node-mounting.nix {
    inherit lib pkgs activeNodes;
    dataDir = cfg.dataDir;
    nodePatches = cfg.nodePatches;
  }) mkNodeSrc nodeBindArgs prepareNodeMountsScript;

  fhsEnv = import ./lib/fhs.nix { inherit pkgs; extraBwrapArgs = nodeBindArgs; };

  inherit (import ./lib/requirements.nix {
    inherit lib pkgs selfHosted cfg comfyCore activeNodes mkNodeSrc fhsEnv;
  }) comfyRequirementsIn venvEnsureScript;

  updateActions = import ./lib/update.nix {
    inherit lib selfHosted cfg activeNodes comfyRequirementsIn;
    requirementsLock = ../../../../../Python/locks/self-hosted/comfyui/requirements.lock;
    # Plain strings, not Nix paths -- those resolve to read-only
    # /nix/store copies, these are the real writable locations in the
    # actual checkout, needed for the :apply variants to sed-edit.
    requirementsLockPath = "${config.vars.identity.homeDirectory}/Dotfiles/Python/locks/self-hosted/comfyui/requirements.lock";
    configFile = "${config.vars.identity.homeDirectory}/Dotfiles/Nixos/config/self-hosted/comfyui/comfyui.nix";
    nodesFile = "${config.vars.identity.homeDirectory}/Dotfiles/Nixos/config/self-hosted/comfyui/catalog/nodes.nix";
  };

  syncModelsScript = import ./lib/models-sync.nix {
    inherit lib activeModels;
    dataDir = cfg.dataDir;
  };

  # Compile-time (pip building extensions) and runtime (nodes that JIT
  # their own CUDA kernels) both need a real toolchain, not just an
  # interpreter -- same values as the old toolchain.sh, minus the
  # Arch-specific /opt/cuda path: CUDA_HOME=/usr because buildFHSEnv
  # merges targetPkgs into a standard FHS layout under /usr inside the
  # sandbox, confirmed when the sandbox itself was built and tested.
  #
  # TORCH_CUDA_ARCH_LIST is the one value here that isn't generically
  # "a toolchain thing" -- it's the CUDA compute capability of your
  # actual GPU (8.6 = Ampere), hardcoded the same way the old
  # toolchain.sh hardcoded it. If the GPU in this machine ever changes,
  # this is the line that needs updating, or CUDA extension builds will
  # target the wrong architecture.
  toolchainEnv = {
    CC = "gcc";
    CXX = "g++";
    NVCC_PREPEND_FLAGS = "-ccbin gcc";
    CXXFLAGS = "-std=c++17";
    TORCH_CUDA_ARCH_LIST = "8.6";
    CUDA_HOME = "/usr";
    PYTHONDONTWRITEBYTECODE = "1";
  };

in
{
  config = lib.mkMerge [
    (selfHosted.mkSelfHostedService {
      name = "comfyui";
      enabled = cfg.enabled;
      user = config.vars.identity.username;
      homeDirectory = config.vars.identity.homeDirectory;
      # --base-directory redirects ComfyUI's models/custom_nodes/input/
      # output/temp/user lookups at the writable dataDir, keeping
      # comfyCore itself (main.py and friends) a plain read-only Nix
      # store path -- confirmed as a real, current ComfyUI CLI flag
      # (comfy/cli_args.py), not assumed. --database-url is a separate,
      # necessary flag on top of that -- confirmed by reading
      # comfy/cli_args.py directly: the sqlite DB path is computed once,
      # at argparse time, as a plain os.path.join relative to
      # cli_args.py's own location (comfyCore, read-only), and
      # --base-directory never touches it afterward (checked main.py's
      # apply_custom_paths(), which only redirects models/output/input/
      # user via folder_paths, nothing database-related) -- a real
      # ComfyUI core gap, not something --base-directory was ever meant
      # to cover. "user" is where ComfyUI defaults to putting it anyway
      # (user/comfyui.db) -- and dataDir/user already exists as a real,
      # vault-backed storage symlink (see storage below), so the
      # database naturally lands with the rest of ComfyUI's actual user
      # data rather than needing its own separate location.
      execStart = "${pkgs.writeShellScript "self-hosted-comfyui-start" ''
        exec ${fhsEnv}/bin/${fhsEnv.name} -c ${lib.escapeShellArg ''
          exec "${cfg.venvDir}/bin/python" ${comfyCore}/main.py \
            --base-directory "${cfg.dataDir}" \
            --database-url "sqlite:///${cfg.dataDir}/user/comfyui.db" \
            --preview-method auto --use-pytorch-cross-attention --lowvram --cuda-device 0
        ''}
      ''}";
      # Reconciliation runs here now, every start, not as separate manual
      # actions: output/temp/input (cheap, --base-directory expects them
      # to exist -- confirmed a real gap: several Comfyroll nodes'
      # INPUT_TYPES() eagerly os.listdir() output/ before ComfyUI itself
      # lazily creates it, throwing FileNotFoundError on first run) ->
      # nodes (cheap, no network) -> venv (needed before execStart's
      # python even runs; mkVenvEnsureScript skips the real install
      # unless requirementsLock actually changed) -> models (network,
      # uses the same environmentFile secrets as everything else on this
      # unit -- EnvironmentFile= applies to every exec step including
      # ExecStartPre, same as the mount check above).
      preStart = [
        "mkdir -p ${cfg.dataDir}/output ${cfg.dataDir}/temp ${cfg.dataDir}/input"
      ]
      # node_data/<repo> (+ any declared extra `dirs`) for every
      # currently-active nodePatches entry -- generated from
      # cfg.nodePatches itself (config/self-hosted/comfyui/catalog/patches.nix),
      # not hardcoded per-node here. Only present at all when at least
      # one patch is active, so nothing runs an empty mkdir.
      ++ lib.optional (nodeDataMkdirScript != "") nodeDataMkdirScript
      ++ [
        prepareNodeMountsScript
        venvEnsureScript
        syncModelsScript
      ];
      packages = [ pkgs.aria2 pkgs.curl pkgs.git ];
      ensureDataDir = true;
      inherit (cfg) dataDir storage autoStart requireMounts teardownPaths;
      venvDir = cfg.venvDir;
      environmentFile = "/etc/nixos-secrets/self-hosted/comfyui/tokens.env";
      # WAS_CONFIG_DIR -- was-node-suite-comfyui already supports this
      # env var natively (its own default is its read-only bind mount,
      # see catalog/patches.nix's "was-node-suite-comfyui" entry for
      # why this lives here as an env var instead of a source patch).
      environment = cfg.environment // toolchainEnv // {
        WAS_CONFIG_DIR = "${cfg.dataDir}/node_data/was-node-suite-comfyui";
      };
    })
    (selfHosted.mkActionService {
      name = "comfyui";
      enabled = cfg.enabled;
      user = config.vars.identity.username;
      # jq/nix/nix-prefetch-git: @update's core/node commit + hash
      # checks. pip-tools: @update:deps' pip-compile -- doesn't need the
      # FHS sandbox, only the actual venv install (now in preStart
      # above) does.
      packages = [
        pkgs.jq
        pkgs.nix
        pkgs.nix-prefetch-git
        pkgs.python312Packages.pip-tools
      ];
      actions = {
      } // updateActions;
    })
    {
      # Buildable without touching the live system: `nix build
      # .#nixosConfigurations.herauxvalle.config.system.build.comfyuiRequirementsIn`
      # -- see comfyRequirementsIn above and this directory's info.md.
      system.build.comfyuiRequirementsIn = comfyRequirementsIn;
    }
    {
      # A typo'd name in installed.nodes/installed.models would otherwise
      # just silently install nothing for that entry -- catch it at
      # rebuild/eval time instead, same as any other Nix config mistake.
      assertions =
        (map
          (n: {
            assertion = builtins.elem n (map (x: x.repo) cfg.nodeStore);
            message = ''vars.selfHosted.comfyui.installed.nodes: "${n}" not found in nodeStore (config/self-hosted/comfyui/catalog/nodes.nix)'';
          })
          cfg.installed.nodes)
        ++ (map
          (n: {
            assertion = builtins.elem n (map (x: x.name) cfg.modelStore);
            message = ''vars.selfHosted.comfyui.installed.models: "${n}" not found in modelStore (config/self-hosted/comfyui/catalog/models.nix)'';
          })
          cfg.installed.models);
    }
  ];
}
