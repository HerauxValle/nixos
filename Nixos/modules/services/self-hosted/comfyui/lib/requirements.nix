{ lib, pkgs, selfHosted, cfg, comfyCore, activeNodes, mkNodeSrc, fhsEnv }:

# The hash-locked venv's requirements.in generation, plus the preStart
# script that actually installs from it. Split out of comfyui.nix once
# that file grew past ~480 lines -- this is the single largest, most
# self-contained chunk (the CUDA/torch pin header alone is ~50 lines of
# real reasoning), and nothing outside this file needs its internals
# beyond the two things exposed below.

let
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
    # No --extra-index-url / +cuXXX tag -- that scheme is obsolete for
    # this PyTorch generation. Checked directly against stock PyPI's JSON
    # API: torch==2.11.0 and torch==2.13.0 both ship as plain
    # (untagged) manylinux wheels there now and declare their own CUDA
    # runtime as ordinary pip deps (nvidia-cudnn-cu13, nvidia-nccl-cu13,
    # cuda-toolkit, triton, ...) instead of baking CUDA into a
    # +cuXXX-tagged wheel pulled from a separate index. The old
    # download.pytorch.org/whl/cu128 index only carries torch up to
    # 2.11.0 and doesn't have 2.13.0 at all -- it's the stale scheme,
    # not stock PyPI.
    #
    # torch is pinned to the 2.11.0 generation (not the newer 2.13.0)
    # because torchaudio's last-ever PyPI release is 2.11.0 -- confirmed
    # by downloading its actual wheel and reading
    # torchaudio-2.11.0.dist-info/METADATA directly: it has zero
    # Requires-Dist entries (not even on torch itself), so it can never
    # be the source of a resolver conflict, but it also can't be
    # expected to work correctly against a torch two generations newer
    # than the last one it ever shipped against. torchvision==0.26.0's
    # own METADATA declares torch==2.11.0 exactly, confirming the pair.
    #
    # The nvidia-cu13/triton/cuda-toolkit/cuda-bindings versions below
    # are copied verbatim from torch==2.11.0's own PyPI Requires-Dist
    # (not left for pip-compile to resolve) -- the seeded lock had these
    # left over from an earlier torch==2.13.0-era resolve, and pip-compile
    # was burning 20-40+ min per run backtracking through each one
    # individually to discover the mismatch. Fully specifying the correct
    # set up front means it only has to verify, not discover.
    torch==2.11.0
    torchvision==0.26.0
    torchaudio==2.11.0
    cuda-toolkit[cublas,cudart,cufft,cufile,cupti,curand,cusolver,cusparse,nvjitlink,nvrtc,nvtx]==13.0.2
    cuda-bindings>=13.0.3,<14
    nvidia-cudnn-cu13==9.19.0.56
    nvidia-cusparselt-cu13==0.8.0
    nvidia-nccl-cu13==2.28.9
    nvidia-nvshmem-cu13==3.4.5
    triton==3.6.0
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
    # separately instead, see venvEnsureScript's extraSteps below.
    sed -i '/^git+https:\/\/github\.com\/facebookresearch\/sam2$/d' $out
    sed -i '/^git+https:\/\/github\.com\/ltdrdata\/img2texture\.git$/d' $out
    sed -i '/^git+https:\/\/github\.com\/ltdrdata\/cstr$/d' $out
    sed -i '/^git+https:\/\/github\.com\/ltdrdata\/ffmpy\.git$/d' $out
  '';

  venvEnsureScript = selfHosted.mkVenvEnsureScript {
    inherit fhsEnv;
    venvDir = cfg.venvDir;
    # Lives under Dotfiles/Python/locks/ -- same convention as OpenWebUI's,
    # a generated pip lockfile doesn't belong next to hand-written .nix.
    requirementsLock = ../../../../../../Python/locks/self-hosted/comfyui/requirements.lock;
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
in
{
  inherit comfyRequirementsIn venvEnsureScript;
}
