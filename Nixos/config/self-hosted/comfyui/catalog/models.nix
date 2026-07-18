
{ ... }:

# The full catalog -- every model ever pinned here, whether or not it's
# currently installed. `name` is the addressable key: list it in
# config.vars.services.selfHosted.comfyui.installed.models (../comfyui.nix) and
# preStart fetches it automatically on the next restart, no manual action
# needed. A handful of entries share a `name` on purpose -- e.g.
# florence2-base's model/config/tokenizer/tokenizer_config are one logical
# model split across 4 files, installing the name gets all of them.
#
# Ported from the old models.sh verbatim (category comments kept for
# readability); the commented-out/disabled entries in that file were left
# out entirely rather than carried over as dead weight.
{
  config.vars.services.selfHosted.comfyui.modelStore = [

    # BASE CHECKPOINTS — SD1.5
    {
      name = "cyberrealistic-fp16-final";
      type = "civitai";
      url = "https://civitai.com/api/download/models/2681234?type=Model&format=SafeTensor&size=pruned&fp=fp16";
      target = "models/checkpoints/cyberrealistic_fp16_Final.safetensors";
    }
    {
      name = "cyberillustrious-fp16-v10-0-redux";
      type = "civitai";
      url = "https://civitai.com/api/download/models/2657063?type=Model&format=SafeTensor&size=pruned&fp=fp16";
      target = "models/checkpoints/cyberillustrious_fp16_v10.0-Redux.safetensors";
    }
    {
      name = "cyberilloustrious-fp16-v11-0";
      type = "civitai";
      url = "https://civitai.red/api/download/models/2879194?type=Model&format=SafeTensor&size=pruned&fp=fp16";
      target = "models/checkpoints/cyberilloustrious_fp16_v11.0.safetensors";
    }
    {
      name = "cyberilloustrious-fp16-v12-0";
      type = "civitai";
      url = "https://civitai.red/api/download/models/3022570?fileId=2901361";
      target = "models/checkpoints/cyberilloustrious_fp16_v12.0.safetensors";
    }

    # BASE CHECKPOINTS — SDXL
    {
      name = "juggernaut-xl-ragnarok";
      type = "civitai";
      url = "https://civitai.com/api/download/models/1759168?type=Model&format=SafeTensor&size=full&fp=fp16";
      target = "models/checkpoints/juggernaut_xl_ragnarok.safetensors";
    }
    {
      name = "realvisxl-v5-0-fp16";
      type = "civitai";
      url = "https://civitai.com/api/download/models/798204?type=Model&format=SafeTensor&size=full&fp=fp16";
      target = "models/checkpoints/RealVisXL_v5.0_fp16.safetensors";
    }
    {
      name = "majicmix-realistic-v7-fp16";
      type = "civitai";
      url = "https://civitai.com/api/download/models/176425?type=Model&format=SafeTensor&size=pruned&fp=fp16";
      target = "models/checkpoints/majicMIX_realistic_v7_fp16.safetensors";
    }
    {
      name = "realistic-vision-v6-0-b1-fp16";
      type = "civitai";
      url = "https://civitai.com/api/download/models/501240?type=Model&format=SafeTensor&size=full&fp=fp16";
      target = "models/checkpoints/realistic-vision_v6.0_B1_fp16.safetensors";
    }
    {
      name = "centerfold-v9-naughty-fp16-sdxl-hyper";
      type = "civitai";
      url = "https://civitai.com/api/download/models/1024110?type=Model&format=SafeTensor&size=pruned&fp=fp16";
      target = "models/checkpoints/centerfold_v9-naughty__fp16_[sdxl-hyper].safetensors";
    }
    {
      name = "nexusdream-infinity-v2-fp16-sdxl-hyper";
      type = "civitai";
      url = "https://civitai.com/api/download/models/2146129?type=Model&format=PickleTensor&size=full&fp=fp16";
      target = "models/checkpoints/nexusDream-infinity_v2_fp16_[sdxl-hyper].safetensors";
    }
    {
      name = "epicrealism-xl-pure-fix-fp16-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/2514955?type=Model&format=SafeTensor&size=pruned&fp=fp16";
      target = "models/checkpoints/epiCRealism-xl_pure-fix_fp16_[sdxl].safetensors";
    }

    # HYPERREALISTIC
    {
      name = "copaxtimeless-xplus-nirai-fp8-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/2528630?type=Model&format=SafeTensor&size=pruned&fp=fp8";
      target = "models/checkpoints/copaxTimeLess_XPlus-Nirai_fp8_[SDXL].safetensors";
    }
    {
      name = "majicmix-realistic-v7-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/176425?type=Model&format=SafeTensor&size=pruned&fp=fp16";
      target = "models/checkpoints/majicMIX-realistic_v7_[sdxl].safetensors";
    }

    # ANIME
    {
      name = "hijklmix-anime-v3-0-fp16-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/360383?type=Model&format=SafeTensor&size=pruned&fp=fp16";
      target = "models/checkpoints/HIJKLMix-Anime_v3.0_fp16_[sdxl].safetensors";
    }
    {
      name = "majicmixrealistic-v6-nigi3d-v1-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/135643?type=Model&format=SafeTensor&size=full&fp=fp16";
      target = "models/checkpoints/majicmixRealistic_v6_nigi3d_v1_[sdxl].safetensors";
    }

    # DIFFUSION MODELS — FLUX
    {
      name = "flux1-dev";
      type = "hf";
      url = "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors?download=true";
      target = "models/diffusion_models/flux1-dev.safetensors";
    }
    {
      name = "flux1-schnell-q4-k-s";
      type = "hf";
      url = "https://huggingface.co/city96/FLUX.1-schnell-gguf/resolve/main/flux1-schnell-Q4_K_S.gguf";
      target = "models/diffusion_models/flux1-schnell-Q4_K_S.gguf";
    }
    {
      name = "flux1-dev-q8-0";
      type = "hf";
      url = "https://huggingface.co/city96/FLUX.1-dev-gguf/resolve/main/flux1-dev-Q8_0.gguf";
      target = "models/diffusion_models/flux1-dev-Q8_0.gguf";
    }
    {
      name = "flux1-dev-q5-k-s";
      type = "hf";
      url = "https://huggingface.co/city96/FLUX.1-dev-gguf/resolve/main/flux1-dev-Q5_K_S.gguf";
      target = "models/diffusion_models/flux1-dev-Q5_K_S.gguf";
    }

    # DIFFUSION MODELS — CHROMA / Z_IMAGE
    {
      name = "z-image-turbo-bf16";
      type = "hf";
      url = "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors?download=true";
      target = "models/diffusion_models/z-image-turbo_bf16.safetensors";
    }
    {
      name = "chroma-unlocked-v35-q8-0";
      type = "hf";
      url = "https://huggingface.co/silveroxides/Chroma-GGUF/resolve/main/chroma-unlocked-v35/chroma-unlocked-v35-Q8_0.gguf";
      target = "models/diffusion_models/chroma-unlocked-v35-Q8_0.gguf";
    }

    # VAEs
    {
      name = "ae";
      type = "hf";
      url = "https://huggingface.co/auroraintech/flux-vae/resolve/main/ae.safetensors";
      target = "models/vae/ae.safetensors";
    }
    {
      name = "vae-z-image-turbo";
      type = "hf";
      url = "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors?download=true";
      target = "models/vae/vae_z-image-turbo.safetensors";
    }
    {
      name = "ema-vae-fp16";
      type = "hf";
      url = "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors?download=true";
      target = "models/vae/ema_vae_fp16.safetensors";
    }

    # TEXT ENCODERS
    {
      name = "clip-l";
      type = "hf";
      url = "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors";
      target = "models/clip/clip_l.safetensors";
    }
    {
      name = "t5xxl-fp8-e4m3fn";
      type = "hf";
      url = "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors";
      target = "models/text_encoders/t5xxl_fp8_e4m3fn.safetensors";
    }
    {
      name = "qwen-3-4b-fp8-mixed";
      type = "hf";
      url = "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b_fp8_mixed.safetensors?download=true";
      target = "models/text_encoders/qwen_3_4b_fp8_mixed.safetensors";
    }

    # UPSCALERS
    {
      name = "4x-ultrasharp";
      type = "civitai";
      url = "https://civitai.com/api/download/models/125843?type=Model&format=PickleTensor";
      target = "models/upscale_models/4x-Ultrasharp.pt";
    }
    {
      name = "realesragan-4xplus";
      type = "hf";
      url = "https://huggingface.co/lllyasviel/Annotators/resolve/main/RealESRGAN_x4plus.pth";
      target = "models/upscale_models/RealESRAGAN_4xplus.pth";
    }

    # CONTROLNET — SD1.5
    {
      name = "lllyasviel-controlnet-v1-1";
      type = "hf";
      url = "https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11f1e_sd15_tile.pth?download=true";
      target = "models/controlnet/lllyasviel_ControlNet-v1-1.pth";
    }

    # CONTROLNET — SDXL
    {
      name = "ttplanet-sdxl-controlnet-tile-realistic";
      type = "hf";
      url = "https://huggingface.co/TTPlanet/TTPLanet_SDXL_Controlnet_Tile_Realistic/resolve/main/TTPLANET_Controlnet_Tile_realistic_v2_fp16.safetensors?download=true";
      target = "models/controlnet/TTPLanet_SDXL_Controlnet_Tile_Realistic.safetensors";
    }

    # IPADAPTER — SDXL MODELS
    {
      name = "ip-adapter-plus-sdxl-vit-h";
      type = "hf";
      url = "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors";
      target = "models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors";
    }
    {
      name = "ip-adapter-plus-face-sdxl-vit-h";
      type = "hf";
      url = "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors";
      target = "models/ipadapter/ip-adapter-plus-face_sdxl_vit-h.safetensors";
    }

    # IPADAPTER — CLIP VISION ENCODERS
    {
      name = "vit-h-14";
      type = "hf";
      url = "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors";
      target = "models/clip_vision/ViT-H-14.safetensors";
    }
    {
      name = "vit-bigg-14";
      type = "hf";
      url = "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors";
      target = "models/clip_vision/ViT-bigG-14.safetensors";
    }

    # IPADAPTER — FACEID LORAS
    {
      name = "ip-adapter-faceid-sdxl";
      type = "hf";
      url = "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid_sdxl.bin";
      target = "models/loras/ip-adapter-faceid_sdxl.bin";
    }
    {
      name = "ip-adapter-faceid-plusv2-sdxl";
      type = "hf";
      url = "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin";
      target = "models/loras/ip-adapter-faceid-plusv2_sdxl.bin";
    }

    # SEGMENTATION & DETECTION — GROUNDING DINO
    {
      name = "grounding-dino-swinb";
      type = "hf";
      url = "https://huggingface.co/ShilongLiu/GroundingDINO/resolve/main/groundingdino_swinb_cogcoor.pth";
      target = "models/grounding-dino/groundingdino_swinb_cogcoor.pth";
    }
    {
      name = "grounding-dino-swinb";
      type = "hf";
      url = "https://huggingface.co/ShilongLiu/GroundingDINO/raw/main/GroundingDINO_SwinB.cfg.py";
      target = "models/grounding-dino/GroundingDINO_SwinB.cfg.py";
    }
    {
      name = "grounding-dino-swint";
      type = "hf";
      url = "https://huggingface.co/ShilongLiu/GroundingDINO/resolve/main/groundingdino_swint_ogc.pth";
      target = "models/grounding-dino/groundingdino_swint_ogc.pth";
    }
    {
      name = "grounding-dino-swint";
      type = "hf";
      url = "https://huggingface.co/ShilongLiu/GroundingDINO/raw/main/GroundingDINO_SwinT_OGC.cfg.py";
      target = "models/grounding-dino/GroundingDINO_SwinT_OGC.cfg.py";
    }

    # SEGMENTATION & DETECTION — SAM
    {
      name = "sam-vit-h-4b8939";
      type = "hf";
      url = "https://huggingface.co/segments-arnaud/sam_vit_h/resolve/main/sam_vit_h_4b8939.pth";
      target = "models/sam/sam_vit_h_4b8939.pth";
    }
    {
      name = "sam-vit-h-4b8939";
      type = "hf";
      url = "https://huggingface.co/segments-arnaud/sam_vit_h/resolve/main/sam_vit_h_4b8939.pth";
      target = "models/sams/sam_vit_h_4b8939.pth";
    }

    # FLORENCE2 — BASE
    {
      name = "florence2-base";
      type = "hf";
      url = "https://huggingface.co/microsoft/Florence-2-base/resolve/main/model.safetensors?download=true";
      target = "models/LLM/florence2-base/model.safetensors";
    }
    {
      name = "florence2-base";
      type = "hf";
      url = "https://huggingface.co/microsoft/Florence-2-base/resolve/main/config.json?download=true";
      target = "models/LLM/florence2-base/config.json";
    }
    {
      name = "florence2-base";
      type = "hf";
      url = "https://huggingface.co/microsoft/Florence-2-base/resolve/main/tokenizer.json?download=true";
      target = "models/LLM/florence2-base/tokenizer.json";
    }
    {
      name = "florence2-base";
      type = "hf";
      url = "https://huggingface.co/microsoft/Florence-2-base/resolve/main/tokenizer_config.json?download=true";
      target = "models/LLM/florence2-base/tokenizer_config.json";
    }

    # FLORENCE2 — LARGE
    {
      name = "florence2-large-ft";
      type = "hf";
      url = "https://huggingface.co/microsoft/Florence-2-large-ft/resolve/main/model.safetensors?download=true";
      target = "models/LLM/florence2-large-ft/model.safetensors";
    }
    {
      name = "florence2-large-ft";
      type = "hf";
      url = "https://huggingface.co/microsoft/Florence-2-large-ft/resolve/main/config.json?download=true";
      target = "models/LLM/florence2-large-ft/config.json";
    }
    {
      name = "florence2-large-ft";
      type = "hf";
      url = "https://huggingface.co/microsoft/Florence-2-large-ft/resolve/main/tokenizer.json?download=true";
      target = "models/LLM/florence2-large-ft/tokenizer.json";
    }
    {
      name = "florence2-large-ft";
      type = "hf";
      url = "https://huggingface.co/microsoft/Florence-2-large-ft/resolve/main/tokenizer_config.json?download=true";
      target = "models/LLM/florence2-large-ft/tokenizer_config.json";
    }

    # FLORENCE2 — COGFLORENCE / VARIANTS
    {
      name = "cogflorence-2-2-large";
      type = "hf";
      url = "https://huggingface.co/thwri/CogFlorence-2.2-Large/resolve/main/model.safetensors?download=true";
      target = "models/LLM/cogflorence-2.2-large/model.safetensors";
    }
    {
      name = "cogflorence-2-2-large";
      type = "hf";
      url = "https://huggingface.co/thwri/CogFlorence-2.2-Large/resolve/main/config.json?download=true";
      target = "models/LLM/cogflorence-2.2-large/config.json";
    }
    {
      name = "cogflorence-2-2-large";
      type = "hf";
      url = "https://huggingface.co/thwri/CogFlorence-2.2-Large/resolve/main/tokenizer.json?download=true";
      target = "models/LLM/cogflorence-2.2-large/tokenizer.json";
    }
    {
      name = "cogflorence-2-2-large";
      type = "hf";
      url = "https://huggingface.co/thwri/CogFlorence-2.2-Large/resolve/main/tokenizer_config.json?download=true";
      target = "models/LLM/cogflorence-2.2-large/tokenizer_config.json";
    }

    # SEEDVR2
    {
      name = "seedvr2-ema-7b-q4-k-m";
      type = "hf";
      url = "https://huggingface.co/AInVFX/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b-Q4_K_M.gguf?download=true";
      target = "models/SEEDVR2/seedvr2_ema_7b-Q4_K_M.gguf";
    }
    {
      name = "seedvr2-ema-7b-sharp-fp8-e4m3fn-mixed-block35-fp16";
      type = "hf";
      url = "https://huggingface.co/AInVFX/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_sharp_fp8_e4m3fn_mixed_block35_fp16.safetensors?download=true";
      target = "models/SEEDVR2/seedvr2_ema_7b_sharp_fp8_e4m3fn_mixed_block35_fp16.safetensors";
    }

    # LORAS — REALISM & LIGHTING
    {
      name = "cinematic-shot-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/481917?type=Model&format=SafeTensor";
      target = "models/loras/cinematic-shot_[sdxl].safetensors";
    }
    {
      name = "cinematic-kodak-motion-picture-v5-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/691212?type=Model&format=SafeTensor";
      target = "models/loras/cinematic-kodak-motion-picture_v5_[sdxl].safetensors";
    }
    {
      name = "analogredmond-analog-style-photography-v2-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/177604?type=Model&format=SafeTensor";
      target = "models/loras/analogredmond-analog-style-photography_v2_[sdxl].safetensors";
    }
    {
      name = "chiaroscuro-lighting-v3-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/691108?type=Model&format=SafeTensor";
      target = "models/loras/chiaroscuro-Lighting_v3_[sdxl].safetensors";
    }
    {
      name = "rembrandt-lighting-style-v2-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/592157?type=Model&format=SafeTensor";
      target = "models/loras/rembrandt-lighting-style_v2_[sdxl].safetensors";
    }
    {
      name = "rmsdxl-darkness-cinema-v1-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/270554?type=Model&format=SafeTensor";
      target = "models/loras/rmsdxl-darkness-cinema_v1_[sdxl].safetensors";
    }
    {
      name = "subtle-lighting-v2xl3-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/1928365?type=Model&format=SafeTensor";
      target = "models/loras/subtle-lighting_v2xl3_[sdxl].safetensors";
    }

    # LORAS — DETAIL & TEXTURE
    {
      name = "touch-of-realism-v2-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/1934796?type=Model&format=SafeTensor";
      target = "models/loras/Touch-of-Realism_v2_[sdxl].safetensors";
    }
    {
      name = "detailed-perfection-style-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/458257?type=Model&format=SafeTensor";
      target = "models/loras/Detailed-Perfection-style_[sdxl].safetensors";
    }
    {
      name = "detail-tweaker-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/135867?type=Model&format=SafeTensor";
      target = "models/loras/detail-tweaker_[sdxl].safetensors";
    }
    {
      name = "add-detailler-slider-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/1506027?type=Model&format=SafeTensor";
      target = "models/loras/add-detailler-slider_[sdxl].safetensors";
    }
    {
      name = "textures-pack-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/335188?type=Model&format=SafeTensor";
      target = "models/loras/textures-pack_[sdxl].safetensors";
    }
    {
      name = "asphalt-cracked-weathered-texture-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/129229?type=Model&format=SafeTensor";
      target = "models/loras/asphalt-cracked-weathered-texture_[sdxl].safetensors";
    }

    # LORAS — PORTRAIT & CHARACTER
    {
      name = "realistic-portrait-midjourney-mimic-v1-rvxl-v4bakedvae-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/532451?type=Model&format=SafeTensor";
      target = "models/loras/realistic-portrait_midjourney-mimic_v1-RVXL-v4BakedVAE_[sdxl].safetensors";
    }
    {
      name = "dreamy-photo-effects-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/795862?type=Model&format=SafeTensor";
      target = "models/loras/dreamy-photo-effects_[sdxl].safetensors";
    }
    {
      name = "realistic-horror-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/518363?type=Model&format=SafeTensor";
      target = "models/loras/realistic-horror_[sdxl].safetensors";
    }

    # LORAS — ENVIRONMENT & FX
    {
      name = "realistic-clouds-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/349930?type=Model&format=SafeTensor";
      target = "models/loras/realistic-clouds_[sdxl].safetensors";
    }
    {
      name = "raindrop-aesthetic-concept-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/509953?type=Model&format=SafeTensor";
      target = "models/loras/raindrop-aesthetic-concept_[sdxl].safetensors";
    }
    {
      name = "under-the-rain-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/388019?type=Model&format=SafeTensor";
      target = "models/loras/under-the-rain_[sdxl].safetensors";
    }
    {
      name = "1204-rain-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/1050658?type=Model&format=SafeTensor";
      target = "models/loras/1204-rain_[sdxl].safetensors";
    }

    # FACE DETECTION WEIGHTS
    {
      name = "codeformer";
      type = "hf";
      url = "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/codeformer.pth";
      target = "models/facerestore_models/codeformer.pth";
    }
    {
      name = "gfpganv1-4";
      type = "hf";
      url = "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/GFPGANv1.4.pth";
      target = "models/facerestore_models/GFPGANv1.4.pth";
    }
    {
      name = "yolov5l-face";
      type = "hf";
      url = "https://huggingface.co/salmonrk/facedetection/resolve/main/yolov5l-face.pth";
      target = "models/facerestore_models/yolov5l-face.pth";
    }

    # LORAS — NSFW
    {
      name = "flat-chest-sdxl-v1";
      type = "civitai";
      url = "https://civitai.com/api/download/models/445135?type=Model&format=SafeTensor";
      target = "models/loras/flat-chest_[sdxl_v1].safetensors";
    }
    {
      name = "sports-bra-underwear-v1-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/175748?type=Model&format=SafeTensor";
      target = "models/loras/sports-bra-underwear_v1_[sdxl].safetensors";
    }
    {
      name = "transparent-clothes-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/344274?type=Model&format=SafeTensor";
      target = "models/loras/transparent-clothes_[sdxl].safetensors";
    }
    {
      name = "girl-pov-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/160622?type=Model&format=SafeTensor";
      target = "models/loras/girl-pov_[sdxl].safetensors";
    }
    {
      name = "spy-cam-changin-room-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/545059?type=Model&format=SafeTensor";
      target = "models/loras/spy-cam-changin-room_[sdxl].safetensors";
    }
    {
      name = "spread-ass-v4-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/285434?type=Model&format=SafeTensor";
      target = "models/loras/spread-ass_v4_[sdxl].safetensors";
    }
    {
      name = "upright-straddle-sex-back-view-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/476281?type=Model&format=SafeTensor";
      target = "models/loras/upright-straddle-sex_back-view_[sdxl].safetensors";
    }
    {
      name = "realistic-futanari-sdxl";
      type = "civitai";
      url = "https://civitai.com/api/download/models/647830?type=Model&format=SafeTensor";
      target = "models/loras/realistic-futanari_[sdxl].safetensors";
    }
  ];
}
