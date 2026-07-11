{ config, lib, pkgs, ... }:

# Wiring -- the FHS sandbox is ./fhs.nix, the generic systemd/venv
# plumbing is ../self-hosted.nix. This file ties those to ComfyUI's own
# values: pinned core source, custom nodes (with the one known patch),
# models, and the install/sync/cleanup actions.
#
# Ported from ~/Scripts/Self-hosted/ComfyUI/, read as a behavioral
# reference only.

let

  selfHosted = import ../self-hosted.nix { inherit lib pkgs; };

  cfg = config.vars.selfHosted.comfyui;

  # The actually-active subsets -- everything below (node symlinking,
  # requirements.in generation, model sync/cleanup) operates on these,
  # never on the full nodeStore/modelStore catalogs directly. Filtering
  # here, once, means every consumer downstream automatically respects
  # installed.nodes/installed.models without re-deriving the same filter.
  activeNodes = builtins.filter (n: builtins.elem n.repo cfg.installed.nodes) cfg.nodeStore;
  activeModels = builtins.filter (m: builtins.elem m.name cfg.installed.models) cfg.modelStore;

  comfyCore = pkgs.fetchFromGitHub {
    owner = "comfyanonymous";
    repo = "ComfyUI";
    rev = cfg.coreRev;
    hash = cfg.coreHash;
  };

  # ComfyUI-post-processing-nodes hardcodes "arial.ttf" as a bare
  # filename (post_processing_nodes.py:108). The old bash resolved this
  # with an Arch-specific hook that symlinked system fonts into
  # /usr/share/fonts/truetype; there's no such dance here -- the FHS
  # sandbox already carries dejavu_fonts, this just points the one
  # hardcoded call at a real path in it. This is a genuine node source
  # bug (a bad hardcoded lookup), not a path-resolution artifact of how
  # nodes get mounted -- unlike the COMFYUI_DIR problem below, patching
  # this at the source is the only real fix, and only this one node
  # needs it.
  mkNodeSrc = node:
    let
      base = pkgs.fetchFromGitHub { inherit (node) owner repo rev hash; };
    in
    if node.repo == "ComfyUI-post-processing-nodes" then
      pkgs.runCommand "node-${node.repo}-patched" { } ''
        cp -r ${base} $out
        chmod -R u+w $out
        sed -i 's|ImageFont\.truetype("arial\.ttf", font_size)|ImageFont.truetype("${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf", font_size)|' \
          "$out/post_processing_nodes.py"
      ''
    else
      base;

  # Bind-mounted, not symlinked -- see ../self-hosted.nix's mkFHSVenv
  # comment for the full reasoning. In short: a plain `ln -sfn` here
  # meant any node computing its own location via
  # `Path(__file__).resolve()` (a common pattern for "find the ComfyUI
  # root") saw the real, flat Nix store path instead of the meaningful
  # dataDir/custom_nodes/<repo> one, breaking on two real nodes
  # (ComfyUI-SAM3, ComfyUI-SAM3DBody) confirmed via actual crashes. A
  # bind mount isn't a symlink to the OS -- .resolve() has nothing to
  # follow through, so this fixes the whole class of bug, not just
  # those two, with no per-node patch needed.
  nodeBindArgs = lib.concatMap
    (node: [ "--ro-bind" "${mkNodeSrc node}" "${cfg.dataDir}/custom_nodes/${node.repo}" ])
    activeNodes;

  fhsEnv = import ./fhs.nix { inherit pkgs; extraBwrapArgs = nodeBindArgs; };

  # bwrap binds *through* the real /home (not a synthetic root section),
  # so every mount point in nodeBindArgs has to already exist as a real
  # directory on the actual host filesystem before the sandbox launches
  # -- confirmed directly (bwrap fails with "No such file or directory"
  # otherwise, and separately, mkdir -p is a no-op over a leftover
  # symlink from the old design, it doesn't replace it -- both caught by
  # actually running this, not assumed). Also removes any leftover
  # directory for a node no longer in installed.nodes, generic
  # reconciliation against real (always-empty-on-the-host) placeholder
  # dirs, not against node content -- the actual source only ever
  # appears inside the sandbox's own mount namespace, never written to
  # the host.
  prepareNodeMountsScript = ''
    set -euo pipefail
    mkdir -p "${cfg.dataDir}/custom_nodes"
    declared_nodes="${lib.concatStringsSep " " (map (n: n.repo) activeNodes)}"
    for node in $declared_nodes; do
      [ -L "${cfg.dataDir}/custom_nodes/$node" ] && rm -f "${cfg.dataDir}/custom_nodes/$node"
      mkdir -p "${cfg.dataDir}/custom_nodes/$node"
    done
    for entry in "${cfg.dataDir}"/custom_nodes/*; do
      [ -e "$entry" ] || continue
      name="$(basename "$entry")"
      keep=0
      for d in $declared_nodes; do
        [ "$d" = "$name" ] && { keep=1; break; }
      done
      [ "$keep" = 1 ] || rm -rf "$entry"
    done
  '';

  # Regenerable requirements.in for the hash-locked venv -- built from
  # activeNodes' own (already-pinned) requirements.txt files plus
  # comfyCore's, so nodes.nix stays the single source of truth instead of
  # a second hand-maintained copy that can silently drift from it. Only
  # currently-installed nodes are included -- no point resolving/locking
  # packages for a node that isn't even installed/mounted. Static
  # header below mirrors the old deps.sh's PYTHON_REQUIREMENTS (pinned
  # via the CUDA index) and PROTECTED_LIBS (hard minimum versions a node
  # must not be allowed to downgrade).
  #
  # To actually update anything (bump a package, add a node whose own
  # requirements.txt pulls in something new): `nix build
  # .#nixosConfigurations.herauxvalle.config.system.build.comfyuiRequirementsIn`,
  # then re-run pip-compile against the result and drop the new lock into
  # Python/locks/self-hosted/comfyui/requirements.lock. See this
  # directory's info.md for the full command.
  comfyRequirementsInHeader = pkgs.writeText "comfyui-requirements-in-header" ''
    --extra-index-url https://download.pytorch.org/whl/cu128

    # Pinned to an exact matched triple, not left unpinned -- leaving
    # them unpinned let pip-compile resolve each independently and pick
    # a real, live mismatch (torch==2.13.0 with no CUDA tag, i.e. a
    # stock CUDA-13.0 build from plain PyPI, alongside
    # torchaudio==2.11.0+cu128 from this index -- ComfyUI's own
    # startup check refuses to run with mismatched CUDA ABIs, confirmed
    # via a real crash loop). torch 2.11.x / torchvision 0.26.x /
    # torchaudio 2.11.x is PyTorch's own release pairing for this line,
    # confirmed by checking https://download.pytorch.org/whl/cu128/ --
    # all three are the latest available there with a cp312 build, all
    # sharing +cu128.
    torch==2.11.0+cu128
    torchvision==0.26.0+cu128
    torchaudio==2.11.0+cu128
    sqlalchemy>=2.0.49
    pandas
    basicsr
    opencv-python-headless
    ninja

    accelerate>=1.3.0
    diffusers>=0.32.0
    peft>=0.14.0
    nvidia-ml-py>=12.535.161
    transformers>=5.5.3
    gpytoolbox>=0.3.7
  '';

  comfyRequirementsIn = pkgs.runCommand "comfyui-requirements.in" { } ''
    cat ${comfyRequirementsInHeader} > $out
    echo "" >> $out

    if [ -f ${comfyCore}/requirements.txt ]; then
      cat ${comfyCore}/requirements.txt >> $out
      echo "" >> $out
    fi

    ${lib.concatMapStringsSep "\n" (node: ''
      if [ -f ${mkNodeSrc node}/requirements.txt ]; then
        cat ${mkNodeSrc node}/requirements.txt >> $out
        echo "" >> $out
      fi
    '') activeNodes}

    # Known, deliberate fixups -- not generic logic, just the two real
    # conflicts this list actually has right now:
    #
    # ComfyUI-BrushNet pins accelerate<0.32.0, directly conflicting with
    # the >=1.3.0 floor above. PROTECTED_LIBS existed precisely to
    # override this kind of node-level downgrade pin -- relax to bare so
    # the floor above governs instead of a hard resolver conflict.
    sed -i 's/^accelerate>=0\.29\.0,<0\.32\.0$/accelerate/' $out

    # These 4 are unpinned git URLs (from ComfyUI-Impact-Pack's and
    # was-node-suite-comfyui's own requirements.txt). pip's
    # --require-hashes mode cannot hash-check a VCS reference at all, and
    # a single unhashed line breaks hashing for the *entire* file -- so
    # they can't be in this list. Pinned to a real commit and installed
    # separately instead, see installScript's extraSteps below.
    sed -i '/^git+https:\/\/github\.com\/facebookresearch\/sam2$/d' $out
    sed -i '/^git+https:\/\/github\.com\/ltdrdata\/img2texture\.git$/d' $out
    sed -i '/^git+https:\/\/github\.com\/ltdrdata\/cstr$/d' $out
    sed -i '/^git+https:\/\/github\.com\/ltdrdata\/ffmpy\.git$/d' $out
  '';

  installScript = selfHosted.mkVenvInstallScript {
    inherit fhsEnv;
    venvDir = cfg.venvDir;
    # Lives under Dotfiles/Python/locks/ -- same convention as OpenWebUI's,
    # a generated pip lockfile doesn't belong next to hand-written .nix.
    requirementsLock = ../../../../../Python/locks/self-hosted/comfyui/requirements.lock;
    # pip's --require-hashes mode rejects a requirements file if even one
    # line lacks a hash, and pip fundamentally cannot hash-check a VCS
    # (git) reference the way it can a sdist/wheel URL -- these 4 packages
    # (pulled in by ComfyUI-Impact-Pack's and was-node-suite-comfyui's own
    # requirements.txt, both unpinned in the upstream source) had to come
    # out of requirements.in entirely rather than break hash-checking for
    # everything else. Pinned to a real commit here (the old bash never
    # pinned these either -- floating git HEAD on every install -- so this
    # is strictly more reproducible, just not hash-verified). --no-deps
    # because their actual dependencies (torch, hydra-core, omegaconf,
    # iopath, ...) are already resolved and hash-locked by the main
    # install above; letting pip re-resolve here could install a
    # different version than the one actually locked.
    extraSteps = ''
      "${cfg.venvDir}/bin/pip" install --no-deps \
        "git+https://github.com/facebookresearch/sam2@2b90b9f5ceec907a1c18123530e92e794ad901a4" \
        "git+https://github.com/ltdrdata/img2texture.git@d6159abea44a0b2cf77454d3d46962c8b21eb9d3" \
        "git+https://github.com/ltdrdata/cstr@0520c29a18a7a869a6e5983861d6f7a4c86f8e9b" \
        "git+https://github.com/ltdrdata/ffmpy.git@f000737698b387ffaeab7cd871b0e9185811230d"
    '';
  };

  updateActions = import ./update.nix {
    inherit lib selfHosted cfg activeNodes comfyRequirementsIn;
    requirementsLock = ../../../../../Python/locks/self-hosted/comfyui/requirements.lock;
    # Plain strings, not Nix paths -- those resolve to read-only
    # /nix/store copies, these are the real writable locations in the
    # actual checkout, needed for the :apply variants to sed-edit.
    requirementsLockPath = "${config.vars.homeDirectory}/Dotfiles/Python/locks/self-hosted/comfyui/requirements.lock";
    configFile = "${config.vars.homeDirectory}/Dotfiles/Nixos/config/self-hosted/comfyui/comfyui.nix";
    nodesFile = "${config.vars.homeDirectory}/Dotfiles/Nixos/config/self-hosted/comfyui/nodes.nix";
  };

  # Extension -> minimum byte size, ported from the old deps.sh's
  # EXPORT_ERROR_CHECK (KB there, bytes here) -- catches truncated/failed
  # downloads that still produced a file, before a later sync silently
  # treats them as "already have it".
  minSizeTable = {
    pth = 10000 * 1000;
    safetensors = 10000 * 1000;
    bin = 10000 * 1000;
    ckpt = 100000 * 1000;
    py = 100 * 1000;
    json = 10 * 1000;
    txt = 10 * 1000;
  };
  minSizeCase = lib.concatStrings (lib.mapAttrsToList
    (ext: bytes: ''"${ext}") min_size=${toString bytes} ;;
'')
    minSizeTable);

  # Space-separated (not newline-separated) so it survives being carried
  # as a plain systemd Environment= value -- same convention Ollama's
  # OLLAMA_MODELS_DECLARED uses and for the same reason. None of the
  # declared urls/targets contain a literal space (checked). Only
  # activeModels -- @sync:models fetches exactly the installed subset and
  # trims disk down to exactly that same subset, both directions in one
  # action (see syncModelsScript below).
  declaredModels = lib.concatMapStringsSep " "
    (m: "${m.type}|${m.url}|${m.target}")
    activeModels;

  # Both directions in one script -- fetch every declared-but-missing
  # model, then remove any file under dataDir/models that isn't backing a
  # currently-installed one. Used to be two separate actions
  # (sync/cleanup, matching the old plugins.sh/cleanup.sh split), merged
  # once the store/installed split made "declared list shrinks" mean
  # "deliberately deactivated, pin still safe in modelStore" rather than
  # "oops, lost the pin" -- removal stopped being the one-way trip that
  # split was originally guarding against.
  syncModelsScript = ''
    set -euo pipefail
    count=0
    for entry in $COMFY_MODELS_DECLARED; do
      IFS='|' read -r type url target <<< "$entry"
      dest="${cfg.dataDir}/$target"
      mkdir -p "$(dirname "$dest")"

      if [ -f "$dest" ]; then
        ext="''${dest##*.}"
        min_size=0
        case "$ext" in
        ${minSizeCase}
        esac
        size="$(stat -c%s "$dest")"
        if [ "$min_size" -gt 0 ] && [ "$size" -lt "$min_size" ]; then
          echo "[corrupt] removing $target (''${size}B < ''${min_size}B)" >&2
          rm -f "$dest"
        else
          echo "[skip] $target"
          count=$((count + 1))
          continue
        fi
      fi

      header=""
      case "$type" in
        hf) [ -n "''${HF_TOKEN:-}" ] && header="Authorization: Bearer $HF_TOKEN" ;;
        civitai) [ -n "''${CIVITAI_TOKEN:-}" ] && header="Authorization: Bearer $CIVITAI_TOKEN" ;;
      esac

      case "$type" in
      git)
        echo "[git] $target"
        git clone --depth=1 "$url" "$dest"
        ;;
      *)
        echo "[download] $target"
        if [ -n "$header" ]; then
          aria2c --dir="$(dirname "$dest")" --out="$(basename "$dest")" --continue=true -x4 -s4 \
            --header="$header" --user-agent="Mozilla/5.0" "$url" \
            || curl -L -f -A "Mozilla/5.0" -H "$header" -o "$dest" "$url"
        else
          aria2c --dir="$(dirname "$dest")" --out="$(basename "$dest")" --continue=true -x4 -s4 \
            --user-agent="Mozilla/5.0" "$url" \
            || curl -L -f -A "Mozilla/5.0" -o "$dest" "$url"
        fi
        ;;
      esac

      if [ -f "$dest" ]; then
        ext="''${dest##*.}"
        min_size=0
        case "$ext" in
        ${minSizeCase}
        esac
        size="$(stat -c%s "$dest")"
        if [ "$min_size" -gt 0 ] && [ "$size" -lt "$min_size" ]; then
          echo "[fail] too small: $target" >&2
          rm -f "$dest"
          continue
        fi
      fi

      count=$((count + 1))
    done
    echo "[sync] $count fetched/kept"

    declared_file="$(mktemp)"
    trap 'rm -f "$declared_file"' EXIT
    for entry in $COMFY_MODELS_DECLARED; do
      IFS='|' read -r _ _ target <<< "$entry"
      echo "${cfg.dataDir}/$target" >> "$declared_file"
    done

    removed=0
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      if ! grep -qxF "$file" "$declared_file"; then
        echo "[remove] $file"
        rm -f "$file"
        removed=$((removed + 1))
      fi
    done < <(find "${cfg.dataDir}/models" -type f 2>/dev/null)
    echo "[sync] $removed removed"
  '';

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
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (selfHosted.mkSelfHostedService {
      name = "comfyui";
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
      preStart = [ prepareNodeMountsScript ];
      ensureDataDir = true;
      inherit (cfg) dataDir storage autoStart requireMounts;
      environmentFile = "/etc/nixos-secrets/self-hosted/comfyui/tokens.env";
      environment = cfg.environment // toolchainEnv;
    })
    (selfHosted.mkActionService {
      name = "comfyui";
      user = config.vars.username;
      # aria2/curl/git: model downloads (@sync:models). jq/nix/
      # nix-prefetch-git: @update's core/node commit + hash checks.
      # pip-tools: @update:deps' pip-compile -- doesn't need the FHS
      # sandbox, only the final venv install does.
      packages = [
        pkgs.aria2
        pkgs.curl
        pkgs.git
        pkgs.jq
        pkgs.nix
        pkgs.nix-prefetch-git
        pkgs.python312Packages.pip-tools
      ];
      environment = { COMFY_MODELS_DECLARED = declaredModels; };
      environmentFile = "/etc/nixos-secrets/self-hosted/comfyui/tokens.env";
      actions = {
        install = installScript;
        # Nodes are no longer sync-able as a standalone action -- they're
        # bind-mounted into the sandbox at build time (nodeBindArgs
        # above), fixed by whatever installed.nodes was at the last
        # rebuild. Activating/deactivating a node is always rebuild +
        # restart now, no separate step in between. models remain the
        # only thing @sync actually reconciles -- sync:models is an
        # alias for consistency with every other service's
        # sync:<target> form, same reasoning as Ollama's sync:models.
        sync = syncModelsScript;
        "sync:models" = syncModelsScript;
        uninstall = selfHosted.mkUninstallScript { inherit (cfg) dataDir storage; venvDir = cfg.venvDir; };
        "uninstall:data" = selfHosted.mkUninstallScript { inherit (cfg) dataDir storage; venvDir = cfg.venvDir; includeData = true; };
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
  ]);
}
