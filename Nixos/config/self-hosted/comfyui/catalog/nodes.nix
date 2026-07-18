# &desc: "Full catalog of 69 ComfyUI custom nodes ever pinned, keyed by repo, nix-prefetch-git via default-branch HEAD at generation time."

{ ... }:

# The full catalog -- all 69 custom nodes ever pinned here (including
# ComfyUI-Manager, not special-cased), whether or not currently installed.
# Pinned via nix-prefetch-git against each repo's default-branch HEAD at
# the time this was generated. `repo` is the addressable key -- list it in
# config.vars.services.selfHosted.comfyui.installed.nodes (../comfyui.nix) to
# actually have it symlinked into custom_nodes/. Category comments kept
# from the old nodes.sh for readability -- purely cosmetic, doesn't affect
# anything.
{
  config.vars.services.selfHosted.comfyui.nodeStore = [
    {
      owner = "ltdrdata";
      repo = "ComfyUI-Manager";
      rev = "351d9c62c419bf49c0fdb6a5a378e94dc3481193";
      hash = "sha256-HtIktmm41dLy+qMbRmMmhnWEpU7agin3jAqTLp7pz3w=";
    }
    {
      owner = "rgthree";
      repo = "rgthree-comfy";
      rev = "27b4f4cdcf3b127c29d5d8135ac1536ecbd4c383";
      hash = "sha256-qFd0OblE70GBej/4L0m/FZIShihWEllKl7yxNk5NOXg=";
    }
    {
      owner = "chrisgoringe";
      repo = "cg-use-everywhere";
      rev = "632ed7bb51bb18ceb03ccaefe1f34be8bd416500";
      hash = "sha256-TWJbdU06FoRFwzxiNcM99muodyISkgvZDlfBR4bMrMc=";
    }
    {
      owner = "pythongosssss";
      repo = "ComfyUI-Custom-Scripts";
      rev = "609f3afaa74b2f88ef9ce8d939626065e3247469";
      hash = "sha256-2GgTS7l/sMSnJb07sBifL8NGnDBF3g9qdlSKr3gYFGQ=";
    }
    {
      owner = "crystian";
      repo = "ComfyUI-Crystools";
      rev = "2f18256c5b5063937106f29a8e0a7db3ae3869b7";
      hash = "sha256-IvLgvudqJV6QeNxwA3HbIlGxShCfUBBSZ8DSjOVlSyE=";
    }
    {
      owner = "pydn";
      repo = "ComfyUI-to-Python-Extension";
      rev = "6cdcc235a06c3354058d606fdd17daf7ca759190";
      hash = "sha256-J7yxyULzTjFDiYRZ9/XNCnmSGfMVZawMAthoTixHRRs=";
    }

    # EASE OF USE & WORKFLOW HELPERS
    {
      owner = "yolain";
      repo = "ComfyUI-Easy-Use";
      rev = "54d080bf6a4f52da287e984f305243c10db097f5";
      hash = "sha256-40q3EN+ThHYyrGplYPFWpL71WR9/KXhbjX2T4uKfxfY=";
    }
    {
      owner = "Smirnov75";
      repo = "ComfyUI-mxToolkit";
      rev = "7f7a0e584f12078a1c589645d866ae96bad0cc35";
      hash = "sha256-0vf6rkDzUvsQwhmOHEigq1yUd/VQGFNLwjp9/P9wJ10=";
    }
    {
      owner = "VykosX";
      repo = "ControlFlowUtils";
      rev = "b675bc6c2c6847d53d8a010fed1497a1b565c144";
      hash = "sha256-hmH+Sp/oHt/aEsaRKIpVxEma5HlktU+O5uW3FuTFblE=";
    }
    {
      owner = "evanspearman";
      repo = "ComfyMath";
      rev = "c01177221c31b8e5fbc062778fc8254aeb541638";
      hash = "sha256-+FSueR6sl2tOrUBL2tT/m506CoS9LyKtXHbWQ/0YFs4=";
    }
    {
      owner = "blepping";
      repo = "ComfyUI-bleh";
      rev = "b889683c425f0870a6192606438fecb7a5bda8b9";
      hash = "sha256-voM8t+zCpTV3AD6xLNaXgKosvhgNGxJ+8Oc4Y8hbYtU=";
    }

    # PROMPT ENGINEERING
    {
      owner = "phazei";
      repo = "ComfyUI-Prompt-Stash";
      rev = "7849791c5908cf3f56bd5da1688108d50c091cda";
      hash = "sha256-iEsxiXCXUqSHDgx/fihNPVHHSZRbdrLKFg0/tjuGo+M=";
    }
    {
      owner = "theUpsider";
      repo = "ComfyUI-Styles_CSV_Loader";
      rev = "255a4af7fcc818c756286c885483a1f97e4f1e9a";
      hash = "sha256-lp/lnJSN3BFXwTggqqL5oHaX6Zv2FpN0Lj1VzIL8ja4=";
    }
    {
      owner = "twri";
      repo = "sdxl_prompt_styler";
      rev = "51068179927f79dce14f38c6b1984390ab242be2";
      hash = "sha256-PXyasD4e4HYHiTvdWNOSaI9jcjZmSRxDWKPdIpm9hAQ=";
    }
    {
      owner = "asagi4";
      repo = "comfyui-prompt-control";
      rev = "139808033bf314948a589a820e8129aed99677c7";
      hash = "sha256-RF5/Oc5awPR+7sVXNIWz5E4OAn14S6LZQ7yuwZNaD7Y=";
    }
    {
      owner = "ialhabbal";
      repo = "ComfyUI-Prompt-Verify";
      rev = "729c4cb84b2c2d87f7598bbca6f6c32c6121b9a9";
      hash = "sha256-hdYFiQApV7birDr0FmNzVs4BzCbp3xv9lb7hJi5rV+s=";
    }
    {
      owner = "stavsap";
      repo = "comfyui-ollama";
      rev = "6db7560576e5a59488708e6be13e07b5aba2432a";
      hash = "sha256-yUv3pZ9Xq8COyIqWOgN4N2UNX6Jx8GMgm5eXOmf0JLI=";
    }

    # SAMPLING & SIGMA CONTROL
    {
      owner = "Jonseed";
      repo = "ComfyUI-Detail-Daemon";
      rev = "39206d10849584e0b6ded943faca4dcd8747beb7";
      hash = "sha256-XmDMQRFJm0/DLhsgzbc/LJS+grITP/CHX+XQmxgfQ4s=";
    }
    {
      owner = "pamparamm";
      repo = "sd-perturbed-attention";
      rev = "904319bff623b185f15047e231a446d615ee48c6";
      hash = "sha256-B7cjhydisRGlUWOgSSm5fttoNoQw1FvNCu41w4/kYSE=";
    }
    {
      owner = "sdtana";
      repo = "ComfyUI-FDG";
      rev = "d9cb3ec24a8ade2c2c44ae3ca2dcb79150590179";
      hash = "sha256-C8hmDkI8o+TkLAN3pMfyPrcJIRKh/6ut3ghTvpxN88I=";
    }
    {
      owner = "BlenderNeko";
      repo = "ComfyUI_TiledKSampler";
      rev = "2fd9b05d97ecffc604c642ffbb40220b182966b2";
      hash = "sha256-Qp1LHlPbUQNKXw2ZVgEgjTvPDMjyqH+QAx47SRc9Yr8=";
    }

    # LATENT MATH & NOISE
    {
      owner = "NicholasMcCarthy";
      repo = "ComfyUI_TravelSuite";
      rev = "c7d76dd5baf4c9bbfe64697350ea0ebc4ae9d434";
      hash = "sha256-jZGfSZxhAPOUDgtwBw44wBwT2NxpIwO0ijV0AqmKpXQ=";
    }
    {
      owner = "FizzleDorf";
      repo = "ComfyUI_FizzNodes";
      rev = "7d6ea60c55ebd1268bd76fa462da052852bff192";
      hash = "sha256-LoF2zCPDh5XK5bYpnnKPj78xkitXqx1861lVqxxGvVQ=";
    }
    {
      owner = "WASasquatch";
      repo = "PowerNoiseSuite";
      rev = "581c164114dcb428759196617c8b18364c80ebeb";
      hash = "sha256-TI2JrlOP1/PPLd4AxcP080F+veB5bqxkSEVdCdD+s+0=";
    }
    {
      owner = "BlenderNeko";
      repo = "ComfyUI_Noise";
      rev = "0c9ec19b16dc72334cb8ce82c3774aed183048e4";
      hash = "sha256-xP/Ev/OknKfAgwcVGBFWhcDrq5sYRbtNogmBeQ1bEAo=";
    }
    {
      owner = "NeuralSamurAI";
      repo = "ComfyUI-Dimensional-Latent-Perlin";
      rev = "72cf9c1aeac606c44d812b104bfdce9b0e73ed8d";
      hash = "sha256-uDGvD8TxsNgaSGhc75HfWKFCj3SHZAsuRZCU7wdWHpk=";
    }
    {
      owner = "kuschanow";
      repo = "ComfyUI-Advanced-Latent-Control";
      rev = "9e685f9f2db8e7883b01a09b4b3ad912f435f9bb";
      hash = "sha256-zRRsDp/YVEwu9ovy3i+iL2ONCUQem6+6s2BznzOscv8=";
    }
    {
      owner = "BlenderNeko";
      repo = "ComfyUI_Cutoff";
      rev = "6c1b1248cbd336000ab1faf779ca603abd560904";
      hash = "sha256-aPbK2XnuGd5JVxAHr5FZPMlZkMUj8gJ8OTL5zmF0pmQ=";
    }

    # IPADAPTER & CONTROLNET
    {
      owner = "cubiq";
      repo = "ComfyUI_IPAdapter_plus";
      rev = "a0f451a5113cf9becb0847b92884cb10cbdec0ef";
      hash = "sha256-Ft9WJcmjzon2tAMJq5na24iqYTnQWEQFSKUElSVwYgw=";
    }
    {
      owner = "Shakker-Labs";
      repo = "ComfyUI-IPAdapter-Flux";
      rev = "eef22b6875ddaf10f13657248b8123d6bdec2014";
      hash = "sha256-sd/krgeQAw19nz6oYUrjXq1KiXMnJ2jV7LjL++AiaA0=";
    }
    {
      owner = "Fannovel16";
      repo = "comfyui_controlnet_aux";
      rev = "e8b689a513c3e6b63edc44066560ca5919c0576e";
      hash = "sha256-tMmERf4y7sfuEGao7JHC7FLjBgPuViCtHxr8f9NnHzo=";
    }

    # DETECTION, SEGMENTATION & MASKING
    {
      owner = "ltdrdata";
      repo = "ComfyUI-Impact-Pack";
      rev = "429d0159ad429e64d2b3916e6e7be9c22d025c3c";
      hash = "sha256-Zom2ugLAnxDhjDxIGO5jpc2oACFD7S8TUkj9rRXN3xI=";
    }
    {
      owner = "ltdrdata";
      repo = "ComfyUI-Inspire-Pack";
      rev = "d23db9aa544de9a6d4c609cb7005fa9e0d42031d";
      hash = "sha256-XjV52EyXQ9pqkntKFB53goJ2oTQ+wjTYQCmE9uVlgJM=";
    }
    {
      owner = "storyicon";
      repo = "comfyui_segment_anything";
      rev = "ab6395596399d5048639cdab7e44ec9fae857a93";
      hash = "sha256-qms+cWLuiJ7Fzc64GLQ4aX4LCiFsugw/sm58iVzrGQw=";
    }
    {
      owner = "PozzettiAndrea";
      repo = "ComfyUI-SAM3";
      rev = "de0ff5d2c2ea435d29f800abfa568cffdfb94773";
      hash = "sha256-BicnmSi3vfrwS8UJcuHhFprNPUOqGjQaDT7DerYE/vg=";
    }
    {
      owner = "kijai";
      repo = "ComfyUI-Florence2";
      rev = "9ece3de914214c5f581d725167bc9d0eeb0d1120";
      hash = "sha256-TlAntRh6US5IkLzY32K5qTpr8KMQQmEQzUeExAHgDJA=";
    }
    {
      owner = "Acly";
      repo = "comfyui-inpaint-nodes";
      rev = "d4a318f00fffbd269418057f869e9bc912832229";
      hash = "sha256-7cmC8IbUeZzEkAObpH9seOOLiaTJTKm9R2c/VNOV+R4=";
    }
    {
      owner = "nullquant";
      repo = "ComfyUI-BrushNet";
      rev = "505d8ef917ddf3896afd1926770ecc9b099704e2";
      hash = "sha256-SwGw97gKno0WjVsSbH1d9kFIK9Aqqjp1fbr1V1akCsU=";
    }
    {
      owner = "1038lab";
      repo = "ComfyUI-RMBG";
      rev = "0ece43adad58fb579e71f81864972d647650889e";
      hash = "sha256-dvkrcRLNIcf2NJYT3fVG9g6I8AqN9X/B6zi5PYOBCt8=";
    }

    # FACE RESTORATION
    {
      owner = "mav-rik";
      repo = "facerestore_cf";
      rev = "ff4d7a5c102441d8f058dd6135797ffb57b6c6ad";
      hash = "sha256-eAlj1QtH5RMSB7O9QkKTraYpPa1LWCyJmZaB3yAVpXc=";
    }

    # UPSCALING
    {
      owner = "ssitu";
      repo = "ComfyUI_UltimateSDUpscale";
      rev = "a5547db9e1d07d3318bb21e9e9c474f4c1e9c8df";
      hash = "sha256-wUN08zn2z/1OLkvSXsfIzJ3/A2FHO5/okeUXEsefEDg=";
    }
    {
      owner = "numz";
      repo = "ComfyUI-SeedVR2_VideoUpscaler";
      rev = "4490bd1f482e026674543386bb2a4d176da245b9";
      hash = "sha256-6nsqFflLw9vYH/du35ET46fdAm1NMjjTe2bA8JmaBE4=";
    }

    # POST-PROCESSING & COLOR GRADING
    {
      owner = "digitaljohn";
      repo = "comfyui-propost";
      rev = "df6a6d122498f57ad7195d58e07701a501c9dcb6";
      hash = "sha256-jUUT8exKWw0aahVZNhX8dY8VJfPQ/qyjVG3M2pdIs6M=";
    }
    {
      owner = "EllangoK";
      repo = "ComfyUI-post-processing-nodes";
      rev = "c49a05254795403648f2c1774b6f5ea39f96e7d5";
      hash = "sha256-/85bl8UH8jmbrgamub942iR4oKxfCZbyhcyWON8wYV4=";
    }
    {
      owner = "o-l-l-i";
      repo = "ComfyUI-OlmLUT";
      rev = "98f19d4ce196d95c3bcced120299669c988a42be";
      hash = "sha256-qFGx8sBKdD0yKLmYQ2tRoZFjyOE7AusVzqoj5yr0yqM=";
    }
    {
      owner = "kijai";
      repo = "ComfyUI-VideoColorGrading";
      rev = "2f6d934bfb71fd047d59838e3171d1a650686d4d";
      hash = "sha256-gGRZ95gvVt7QjhroS3VEvwobth5kiX35r95PlWiW1kg=";
    }
    {
      owner = "lquesada";
      repo = "ComfyUI-Inpaint-CropAndStitch";
      rev = "3617559bcb9d15ff60b24c6800701402eb2cd478";
      hash = "sha256-Uo9wjkskUpCeh5EPo7PPDc7DBbgwVq9/g1X33naowR8=";
    }

    # OUTPUT & METADATA
    {
      owner = "spacepxl";
      repo = "ComfyUI-HQ-Image-Save";
      rev = "44b0c6f769a1e90d986308ccc7d83851216e191d";
      hash = "sha256-/rdV9ANDmFO4OoKrDKY796lrBjGS7TB6buqnxg3mywE=";
    }
    {
      owner = "ltdrdata";
      repo = "was-node-suite-comfyui";
      rev = "44de705818d4663fefefde57ffe0ea5a9ea39df4";
      hash = "sha256-jqUI1ZqDlazqtxrF17yPsuygt2yi4mio/xqGdHCp6z8=";
    }

    # ADVANCED ARCHITECTURE (ROI / PRODUCTION)
    {
      owner = "city96";
      repo = "ComfyUI-GGUF";
      rev = "6ea2651e7df66d7585f6ffee804b20e92fb38b8a";
      hash = "sha256-/ZwecgxTTMo9J1whdEJci8lEkOy/yP+UmjbpOAA3BvU=";
    }
    {
      owner = "Kosinkadink";
      repo = "ComfyUI-VideoHelperSuite";
      rev = "4ee72c065db22c9d96c2427954dc69e7b908444b";
      hash = "sha256-uq1H6EH8oVqjhVAn+lPLRS5WohTncGbpKH6jZk/bbaI=";
    }
    {
      owner = "Acly";
      repo = "comfyui-tooling-nodes";
      rev = "5d3194f4d4158ab31df7a060e1e4c56fa03f320c";
      hash = "sha256-1XesupLKvy2MS4TUpDzaLrP/14JdUeyng14z49PZ8b4=";
    }
    {
      owner = "SeargeDP";
      repo = "SeargeSDXL";
      rev = "2eb5edbc712329d77d1a2f5f1e6c5e64397a4a83";
      hash = "sha256-m8S2ZnzsIwZo+GaPX6cWeDNLomrAVivADGwQGDpHx+E=";
    }
    {
      owner = "cubiq";
      repo = "ComfyUI_essentials";
      rev = "9d9f4bedfc9f0321c19faf71855e228c93bd0dc9";
      hash = "sha256-wkwkZVZYqPgbk2G4DFguZ1absVUFRJXYDRqgFrcLrfU=";
    }
    {
      owner = "melMass";
      repo = "comfy_mtb";
      rev = "b35b5d8a17c0d59e80a8b3627b679c2c1003d04f";
      hash = "sha256-ykidw7DSUxhFnIDwoa63iLmTX2xrup0OzXmekMZv/sA=";
    }
    {
      owner = "Kosinkadink";
      repo = "ComfyUI-AnimateDiff-Evolved";
      rev = "d8d163cd90b1111f6227495e3467633676fbb346";
      hash = "sha256-Pe4xuZSIaeHanXID0WPE4v5sgdhA990z1oqqEVagjcc=";
    }
    {
      owner = "ZHO-ZHO-ZHO";
      repo = "ComfyUI-Gemini";
      rev = "98d91fc2340d23c671c2e1425c2ce62ce2f8c2c1";
      hash = "sha256-qVMRaRFREjC5WJ2du1L58X3OkJbmSRIA0mPYYPUHRhg=";
    }

    # ATTENTION & CFG CONTROL
    {
      owner = "Extraltodeus";
      repo = "ComfyUI-AutomaticCFG";
      rev = "2e395317b65c05a97a0ef566c4a8c7969305dafa";
      hash = "sha256-Kc7JK53V3ptypJUNTyE4OPSZzWhIMYBAak6aJRZsscU=";
    }
    {
      owner = "huchenlei";
      repo = "ComfyUI-layerdiffuse";
      rev = "b4f6a9e024064a4489f774a8b91049ce0b606ea3";
      hash = "sha256-yQBsFf903zP2C1e3/Y+142dH4Ysg4ORj87a5c52w4B4=";
    }

    # FREQUENCY & IMAGE FILTERS
    {
      owner = "spacepxl";
      repo = "ComfyUI-Image-Filters";
      rev = "bbb3fb0045461adf3602faeedaf40af57090d4e2";
      hash = "sha256-k3mGUmepmhXhJL6b3fF9pkIgph1PpqXE+hrufdnv5Tg=";
    }

    # TAGGING & PROMPT REVERSE-ENGINEERING
    {
      owner = "pythongosssss";
      repo = "ComfyUI-WD14-Tagger";
      rev = "9e0a6e700299182fc05c58b62e7ad9f72182a78b";
      hash = "sha256-ww3KpXR5gpDdVKWipYMtqkCTh5iLpqLaenGto0Z28WQ=";
    }

    # 3D GENERATION & PROCESSING
    {
      owner = "kijai";
      repo = "ComfyUI-Hunyuan3DWrapper";
      rev = "2609efa38f6a98292476f714839b7c1e5f9b699a";
      hash = "sha256-JBUPP48tIBogXOxF94KbPjEWgZQztw2XyL8iRvP1OC8=";
    }
    {
      owner = "jtydhr88";
      repo = "ComfyUI-qwenmultiangle";
      rev = "93efd354a002f9c6add7e948663cf459528242da";
      hash = "sha256-KY3UWTxplaMdA5/uEzprmmkwe4RitlSlbzQElbr6HZw=";
    }
    {
      owner = "PozzettiAndrea";
      repo = "ComfyUI-SAM3DBody";
      rev = "9aaff445a2802c07e8c8ec136cd7357b76c8423e";
      hash = "sha256-+F7mc+cgl+sIi9hWtYKG/K0v4w7+3lGUPF/B1cp3oVw=";
    }

    # EXTRAS / NICHE
    {
      owner = "Suzie1";
      repo = "ComfyUI_Comfyroll_CustomNodes";
      rev = "d78b780ae43fcf8c6b7c6505e6ffb4584281ceca";
      hash = "sha256-+qhDJ9hawSEg9AGBz8w+UzohMFhgZDOzvenw8xVVyPc=";
    }
    {
      owner = "kijai";
      repo = "ComfyUI-KJNodes";
      rev = "e27a505b3ba6ce42687fe00500deda103d9d6071";
      hash = "sha256-WutSBirMittIh6rVDMgEjPfRKK2duzjZ4sN6A/QHRKA=";
    }
    {
      owner = "bytedance";
      repo = "ComfyUI-HyperLoRA";
      rev = "108d4c32eb6bb77d386a6fb1a3d05d6826df8bcd";
      hash = "sha256-ak9xBOh2T9+0Ghdk8cJL6K1MPbTKjr89hdxRUwjis60=";
    }
    {
      owner = "comfyanonymous";
      repo = "ComfyUI_TensorRT";
      rev = "5bcc3f1e5c2424bb20bcb586e340c25ebe4a954f";
      hash = "sha256-tqiodF60IVlmvJknYxEwL0U7GIrrfl49k6Tg+8jGRVU=";
    }
    {
      owner = "LAOGOU-666";
      repo = "ComfyUI-LG_HotReload";
      rev = "d71ea0ea7938744ce8e8c853b6de729c2a3503ea";
      hash = "sha256-WLwYsrurDcYsqX/NJ1WTTzYKIa4fo2osKtuub5aqdFE=";
    }

    # "https://github.com/AIGODLIKE/AIGODLIKE-ComfyUI-Studio"
  ];
}
