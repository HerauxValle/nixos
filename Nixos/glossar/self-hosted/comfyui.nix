{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.selfHosted.comfyui option, all commented
# out. Same shape as glossar/main/variables.nix, scoped to one service.
# Schema: modules/services/self-hosted/comfyui/default.nix. Real values on
# this machine: config/self-hosted/comfyui/{comfyui,catalog/*}.nix. Full
# reference (systemd units, workflows, "why" for every mechanism below):
# modules/services/self-hosted/comfyui/info.md.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste reference.
# Copy a block (or a line out of one) into config/self-hosted/comfyui/*.nix
# and uncomment it there to actually set it. Terse, ini-style companion to
# that service's info.md -- regenerate by hand alongside it, nothing keeps
# either in sync automatically.
# =========================================================================

{
  # config.vars.selfHosted.comfyui = {

  #   # --- master switch --------------------------------------------------
  #   # true = live service + actions exist and run. false = torn down
  #   # automatically on the next rebuild (venv, custom_nodes/, models/ --
  #   # see teardownPaths below), not just absent.
  #   enabled = false;

  #   # --- paths -------------------------------------------------------------
  #   dataDir = "${homeDirectory}/Applications/Networking/ComfyUI";  # holds custom_nodes/ (bind mounts), models/, user/ (via storage), output/temp/input, node_data/ (per-patched-node writable data)
  #   venvDir = "${homeDirectory}/.impure/python-venvs/self-hosted/comfyui";  # disposable, regenerated automatically whenever requirementsLock's hash changes

  #   autoStart = true;  # false = exists, systemctl start-able, but not on boot/rebuild

  #   # --- live process env, merged with a fixed toolchainEnv (CC/CXX/CUDA_HOME/etc) and WAS_CONFIG_DIR --
  #   environment = {
  #     SOME_VAR = "value";
  #   };

  #   # --- vault-backed real data -- symlinked at rebuild time -------------
  #   storage = [
  #     { src = "user"; dest = "${homeDirectory}/Images/SelfHosted/ComfyUI/user"; }
  #   ];

  #   # --- must already be a mountpoint before this service (or its preStart) runs --
  #   requireMounts = [ "${homeDirectory}/Images/SelfHosted" ];

  #   # --- what enabled=false actually removes -------------------------------
  #   # Non-empty here, deliberately: dataDir also holds output/temp/input
  #   # (real generated/uploaded content, no storage entry covers it), so
  #   # the usual empty-default "everything but storage" teardown would
  #   # destroy it. Only these two paths are ever removed; venvDir is
  #   # always removed too, separately, regardless of this list.
  #   teardownPaths = [ "custom_nodes" "models" ];

  #   # --- pinned core commit -- both required together --------------------
  #   coreRev = "0123456789abcdef0123456789abcdef01234567";
  #   coreHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  #   # --- full node catalog -- every node ever pinned, active or not ------
  #   # repo is the addressable key: reference it in installed.nodes to
  #   # activate it. Get rev+hash with nix-prefetch-git.
  #   nodeStore = [
  #     { owner = "someone"; repo = "ComfyUI-SomeNode"; rev = "0123456789abcdef0123456789abcdef01234567"; hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; }
  #   ];

  #   # --- per-node source patches, keyed by nodeStore's repo name ----------
  #   # script (optional) -- shell fragment run against a writable copy of
  #   # that node's source before it's bind-mounted in (fixes a node's own
  #   # hardcoded read-only-write bug). dirs (optional) -- extra paths,
  #   # relative to dataDir/node_data/<repo>, pre-created in preStart before
  #   # the node's code runs. Either can be omitted; an entry can exist for
  #   # just its dirs with no script at all.
  #   nodePatches = [
  #     {
  #       repo = "ComfyUI-SomeNode";
  #       script = ''
  #         sed -i 's|some_old_pattern|some_new_pattern|' "$out/some_file.py"
  #       '';
  #       dirs = [ "some/nested/writable/path" ];
  #     }
  #   ];

  #   # --- full model catalog -- ~700GB across all of them, never all installed at once --
  #   # name is the addressable key for installed.models (not required to
  #   # be unique -- entries sharing a name are one logical model split
  #   # across files, installed/removed together). type is hf|civitai|git|url.
  #   modelStore = [
  #     { name = "some-model"; type = "hf"; url = "https://huggingface.co/someone/some-model/resolve/main/model.safetensors"; target = "models/checkpoints/some-model.safetensors"; }
  #   ];

  #   # --- the actually-active subset -- everything else stays pinned but inert --
  #   installed = {
  #     nodes = [ "ComfyUI-SomeNode" ];  # repo values from nodeStore -- unknown name = hard eval-time error
  #     models = [ "some-model" ];        # name values from modelStore -- unknown name = hard eval-time error
  #   };

  # };
}
