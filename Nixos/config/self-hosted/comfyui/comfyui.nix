{ config, ... }:

# Everything that isn't the node/model lists -- those live in
# ./nodes.nix and ./models.nix, split out purely because of their size.
{
  config.vars.selfHosted.comfyui = {
    # true = installed: systemd units exist, preStart/postStart
    # reconciliation runs. false = torn down on the next rebuild --
    # venvDir, custom_nodes/, models/ all removed automatically, but
    # storage (the "user" vault entry) and dataDir's other real content
    # (output/, temp/, input/) are never touched by that teardown.
    enabled = true;

    dataDir = "${config.vars.homeDirectory}/Applications/Networking/ComfyUI";

    # Off for now -- still exists, still systemctl start-able by hand,
    # just not pulled in on boot/rebuild.
    autoStart = false;

    # Update together with nodes.nix's own entries -- see
    # ../../../modules/services/self-hosted/comfyui/default.nix for how
    # to get a new hash when bumping the pinned commit.
    coreRev = "f3a36e74844893f32f77f22d249d08862805d8f4";
    coreHash = "sha256-upBshlNlkK9Os4fhvrETqmxd9yi9UAVxPbCkomOLIH4=";

    # The one real data location -- inside the SelfHosted Casket vault,
    # same one Stash/OpenWebUI use. Matches the old COMFY_STORAGE entry
    # exactly (not the "Vaults" vault the old obsidian-unlock.sh hook
    # referenced -- same stale-hook pattern already confirmed for
    # OpenWebUI, dropped here too).
    storage = [
      { src = "user"; dest = "${config.vars.homeDirectory}/Images/SelfHosted/ComfyUI/user"; }
    ];

    requireMounts = [ "${config.vars.homeDirectory}/Images/SelfHosted" ];

    # Non-empty, deliberately -- dataDir also holds output/temp/input
    # (real generated/uploaded content, no storage entry covers them), so
    # the default "everything but storage" teardown would delete them.
    # Only these two paths are ever removed when enabled = false; the
    # venv (venvDir, outside dataDir) is always removed too regardless.
    teardownPaths = [ "custom_nodes" "models" ];

    # nodeStore/modelStore (./nodes.nix, ./models.nix) are the full
    # catalog -- everything ever pinned. This is the actually-active
    # subset: only these get symlinked/fetched/kept.
    installed = {
      # All 69 -- these were already running together on the old Arch
      # setup, no known conflicts between them, so nothing to trim here.
      nodes = [
        "ComfyUI-Manager"
        "rgthree-comfy"
        "cg-use-everywhere"
        "ComfyUI-Custom-Scripts"
        "ComfyUI-Crystools"
        "ComfyUI-to-Python-Extension"
        "ComfyUI-Easy-Use"
        "ComfyUI-mxToolkit"
        "ControlFlowUtils"
        "ComfyMath"
        "ComfyUI-bleh"
        "ComfyUI-Prompt-Stash"
        "ComfyUI-Styles_CSV_Loader"
        "sdxl_prompt_styler"
        "comfyui-prompt-control"
        "ComfyUI-Prompt-Verify"
        "comfyui-ollama"
        "ComfyUI-Detail-Daemon"
        "sd-perturbed-attention"
        "ComfyUI-FDG"
        "ComfyUI_TiledKSampler"
        "ComfyUI_TravelSuite"
        "ComfyUI_FizzNodes"
        "PowerNoiseSuite"
        "ComfyUI_Noise"
        "ComfyUI-Dimensional-Latent-Perlin"
        "ComfyUI-Advanced-Latent-Control"
        "ComfyUI_Cutoff"
        "ComfyUI_IPAdapter_plus"
        "ComfyUI-IPAdapter-Flux"
        "comfyui_controlnet_aux"
        "ComfyUI-Impact-Pack"
        "ComfyUI-Inspire-Pack"
        "comfyui_segment_anything"
        "ComfyUI-SAM3"
        "ComfyUI-Florence2"
        "comfyui-inpaint-nodes"
        "ComfyUI-BrushNet"
        "ComfyUI-RMBG"
        "facerestore_cf"
        "ComfyUI_UltimateSDUpscale"
        "ComfyUI-SeedVR2_VideoUpscaler"
        "comfyui-propost"
        "ComfyUI-post-processing-nodes"
        "ComfyUI-OlmLUT"
        "ComfyUI-VideoColorGrading"
        "ComfyUI-Inpaint-CropAndStitch"
        "ComfyUI-HQ-Image-Save"
        "was-node-suite-comfyui"
        "ComfyUI-GGUF"
        "ComfyUI-VideoHelperSuite"
        "comfyui-tooling-nodes"
        "SeargeSDXL"
        "ComfyUI_essentials"
        "comfy_mtb"
        "ComfyUI-AnimateDiff-Evolved"
        "ComfyUI-Gemini"
        "ComfyUI-AutomaticCFG"
        "ComfyUI-layerdiffuse"
        "ComfyUI-Image-Filters"
        "ComfyUI-WD14-Tagger"
        "ComfyUI-Hunyuan3DWrapper"
        "ComfyUI-qwenmultiangle"
        "ComfyUI-SAM3DBody"
        "ComfyUI_Comfyroll_CustomNodes"
        "ComfyUI-KJNodes"
        "ComfyUI-HyperLoRA"
        "ComfyUI_TensorRT"
        "ComfyUI-LG_HotReload"
      ];

      # Deliberately empty -- modelStore is ~700GB across every entry,
      # there's no world where all of it is wanted on disk at once. Fill
      # in the `name`s (from ./models.nix) you actually want fetched --
      # preStart picks it up automatically on the next restart; everything
      # else stays pinned in the catalog, ready to add later without
      # re-deriving anything.
      models = [ ];
    };
  };
}
