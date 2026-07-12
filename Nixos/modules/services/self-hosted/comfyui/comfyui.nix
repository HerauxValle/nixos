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

  cfg = config.vars.selfHosted.comfyui;

  # The actually-active subsets -- everything below (node mounting,
  # requirements.in generation, model sync) operates on these, never on
  # the full nodeStore/modelStore catalogs directly. Filtering here, once,
  # means every consumer downstream automatically respects
  # installed.nodes/installed.models without re-deriving the same filter.
  activeNodes = builtins.filter (n: builtins.elem n.repo cfg.installed.nodes) cfg.nodeStore;
  activeModels = builtins.filter (m: builtins.elem m.name cfg.installed.models) cfg.modelStore;

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
    requirementsLockPath = "${config.vars.homeDirectory}/Dotfiles/Python/locks/self-hosted/comfyui/requirements.lock";
    configFile = "${config.vars.homeDirectory}/Dotfiles/Nixos/config/self-hosted/comfyui/comfyui.nix";
    nodesFile = "${config.vars.homeDirectory}/Dotfiles/Nixos/config/self-hosted/comfyui/nodes.nix";
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
      user = config.vars.username;
      homeDirectory = config.vars.homeDirectory;
      # --base-directory redirects ComfyUI's models/custom_nodes/input/
      # output/temp/user lookups at the writable dataDir, keeping
      # comfyCore itself (main.py and friends) a plain read-only Nix
      # store path -- confirmed as a real, current ComfyUI CLI flag
      # (comfy/cli_args.py), not assumed.
      execStart = "${pkgs.writeShellScript "self-hosted-comfyui-start" ''
        exec ${fhsEnv}/bin/${fhsEnv.name} -c ${lib.escapeShellArg ''
          exec "${cfg.venvDir}/bin/python" ${comfyCore}/main.py \
            --base-directory "${cfg.dataDir}" \
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
        prepareNodeMountsScript
        venvEnsureScript
        syncModelsScript
      ];
      packages = [ pkgs.aria2 pkgs.curl pkgs.git ];
      ensureDataDir = true;
      inherit (cfg) dataDir storage autoStart requireMounts teardownPaths;
      venvDir = cfg.venvDir;
      environmentFile = "/etc/nixos-secrets/self-hosted/comfyui/tokens.env";
      environment = cfg.environment // toolchainEnv;
    })
    (selfHosted.mkActionService {
      name = "comfyui";
      enabled = cfg.enabled;
      user = config.vars.username;
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
            message = ''vars.selfHosted.comfyui.installed.nodes: "${n}" not found in nodeStore (config/self-hosted/comfyui/nodes.nix)'';
          })
          cfg.installed.nodes)
        ++ (map
          (n: {
            assertion = builtins.elem n (map (x: x.name) cfg.modelStore);
            message = ''vars.selfHosted.comfyui.installed.models: "${n}" not found in modelStore (config/self-hosted/comfyui/models.nix)'';
          })
          cfg.installed.models);
    }
  ];
}
