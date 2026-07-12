{ config, pkgs, ... }:

# Real per-node source patches -- split out from comfyui.nix purely for
# size/clarity, same convention as nodes.nix/models.nix. Deliberately
# takes `pkgs` (unlike nodes.nix/models.nix, which are pure data with no
# package references) -- a patch's fix sometimes has to point at a real
# package path (the font fix below points at pkgs.dejavu_fonts). A
# narrow, intentional exception to this directory's usual "never pkgs"
# rule for exactly this reason, not a general license to add logic here.
let
  # All six write-target patches below share this: each node hardcodes
  # a write location "next to my own source file" (or, worse, next to
  # __main__.__file__ -- comfyCore's own entry point), and both of those
  # are deliberately read-only (comfyCore for reproducibility, each
  # node's own bind mount for the same reason -- see
  # ../../../modules/services/self-hosted/comfyui/info.md's "Node
  # mounting" section). The fix in every case is the same shape:
  # redirect that one hardcoded base to a real writable location under
  # dataDir instead. `node_data/<repo>` is that convention -- one
  # subdirectory per patched node, created in comfyui.nix's preStart.
  dataDir = config.vars.selfHosted.comfyui.dataDir;
  nodeDataDir = repo: "${dataDir}/node_data/${repo}";
in
{
  config.vars.selfHosted.comfyui.nodePatches = [
    {
      # ComfyUI-post-processing-nodes hardcodes "arial.ttf" as a bare
      # filename (post_processing_nodes.py:108). The old bash resolved
      # this with an Arch-specific hook that symlinked system fonts into
      # /usr/share/fonts/truetype; there's no such dance here -- the FHS
      # sandbox already carries dejavu_fonts, this just points the one
      # hardcoded call at a real path in it.
      repo = "ComfyUI-post-processing-nodes";
      script = ''
        sed -i 's|ImageFont\.truetype("arial\.ttf", font_size)|ImageFont.truetype("${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf", font_size)|' \
          "$out/post_processing_nodes.py"
      '';
    }

    {
      # __init__.py:14-15 computes its web-extension install target as
      # os.path.dirname(os.path.realpath(__main__.__file__)) + "web/
      # extensions/FizzleDorf" -- __main__.__file__ is comfyCore's own
      # main.py, so this resolves into the read-only Nix store.
      # os.makedirs (already recursive) handles creating the rest of the
      # path once the base is redirected -- no further patch needed.
      repo = "ComfyUI_FizzNodes";
      script = ''
        sed -i 's|os\.path\.dirname(os\.path\.realpath(__main__\.__file__))|"${nodeDataDir "ComfyUI_FizzNodes"}"|' \
          "$out/__init__.py"
      '';
    }

    {
      # Same __main__.__file__-relative pattern as FizzNodes
      # (__init__.py:10-11), but also uses a single-level os.mkdir
      # (not os.makedirs) for the final "web/extensions/Gemini_Zho"
      # path -- redirecting the base alone isn't enough, since
      # os.mkdir requires its immediate parent to already exist and
      # nodeDataDir's freshly-created directory has no web/extensions/
      # subpath yet. Patched to os.makedirs(..., exist_ok=True) too,
      # same fix shape as the FizzNodes/UltimateSDUpscale cases where
      # the original code already used the recursive form.
      repo = "ComfyUI-Gemini";
      script = ''
        sed -i 's|os\.path\.dirname(os\.path\.realpath(__main__\.__file__))|"${nodeDataDir "ComfyUI-Gemini"}"|' \
          "$out/__init__.py"
        sed -i 's|os\.mkdir(extentions_folder)|os.makedirs(extentions_folder, exist_ok=True)|' \
          "$out/__init__.py"
      '';
    }

    {
      # pysssss.py (bundled identically by both this node and
      # WD14-Tagger below) has two independent base-path functions:
      # get_ext_dir() -- os.path.dirname(__file__), this node's own
      # read-only bind mount, used for pysssss.json config storage --
      # and get_comfy_dir() -- os.path.dirname(inspect.getfile(
      # PromptServer)), comfyCore's own read-only Nix store path, used
      # for the web/extensions/pysssss symlink target. Both redirected
      # to the same per-node writable dir -- get_comfy_dir's actual
      # semantic intent ("the real Comfy install root") is best served
      # by nodeDataDir here rather than a genuinely shared location,
      # since nothing else needs to read what it writes. Both
      # functions already use os.makedirs (recursive), no mkdir/
      # makedirs fix needed.
      repo = "ComfyUI-Custom-Scripts";
      script = ''
        sed -i 's|dir = os\.path\.dirname(__file__)|dir = "${nodeDataDir "ComfyUI-Custom-Scripts"}"|' \
          "$out/pysssss.py"
        sed -i 's|dir = os\.path\.dirname(inspect\.getfile(PromptServer))|dir = "${nodeDataDir "ComfyUI-Custom-Scripts"}"|' \
          "$out/pysssss.py"
      '';
    }

    {
      # Identical bundled pysssss.py, same two functions, same fix --
      # its own separate node_data subdirectory (not shared with
      # Custom-Scripts, even though both use the "pysssss" name
      # internally -- keeping every patched node's writable data under
      # its own nodeDataDir is the one consistent rule here, no
      # exceptions to remember).
      repo = "ComfyUI-WD14-Tagger";
      script = ''
        sed -i 's|dir = os\.path\.dirname(__file__)|dir = "${nodeDataDir "ComfyUI-WD14-Tagger"}"|' \
          "$out/pysssss.py"
        sed -i 's|dir = os\.path\.dirname(inspect\.getfile(PromptServer))|dir = "${nodeDataDir "ComfyUI-WD14-Tagger"}"|' \
          "$out/pysssss.py"
      '';
    }

    {
      # __init__.py:8 computes current_dir the same way as repo_dir at
      # line 41 (os.path.dirname(os.path.realpath(__file__))) -- but
      # repo_dir (line 41) is added to sys.path for this node's own
      # sibling-module imports and must keep pointing at the real
      # source, so only line 8's assignment is targeted (anchored on
      # "^current_dir = ", not a global replace). current_dir is used
      # to self-download-and-extract a third-party dependency
      # (ultimate-upscale-for-automatic1111) into
      # current_dir/repositories/ultimate_sd_upscale on first run,
      # checked via os.listdir(usdu_dir) -- which raises
      # FileNotFoundError outright if usdu_dir doesn't exist yet.
      # Declared via dirs below (generates a real preStart mkdir -p)
      # rather than inserting an os.makedirs call into the node's own
      # source -- same outcome, but the "this node needs a directory to
      # exist" fact stays visible as data instead of being buried in a
      # second sed patch.
      repo = "ComfyUI_UltimateSDUpscale";
      script = ''
        sed -i 's|^current_dir = os\.path\.dirname(os\.path\.realpath(__file__))|current_dir = "${nodeDataDir "ComfyUI_UltimateSDUpscale"}"|' \
          "$out/__init__.py"
      '';
      dirs = [ "repositories/ultimate_sd_upscale" ];
    }

    {
      # __init__.py has three separate os.path.dirname(__file__)-based
      # targets -- wildcards_path (line 25), styles_path/samples_path
      # (lines 38-39) -- and unlike UltimateSDUpscale, all three are
      # genuinely write targets (a bundled wildcards/ and styles/
      # directory the node creates on first run if missing), not a
      # mix of read+write uses -- confirmed by reading the surrounding
      # code, not assumed. A global replace is correct here specifically
      # because every occurrence needs the same fix, not despite there
      # being multiple occurrences.
      repo = "ComfyUI-Easy-Use";
      script = ''
        sed -i 's|os\.path\.dirname(__file__)|"${nodeDataDir "ComfyUI-Easy-Use"}"|g' \
          "$out/__init__.py"
      '';
    }
  ];
}
