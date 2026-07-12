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
  # ../../../../modules/services/self-hosted/comfyui/info.md's "Node
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
      #
      # get_ext_dir() -- os.path.dirname(__file__), this node's own
      # read-only bind mount -- must NOT be redirected wholesale: it's
      # used for real reads too (get_ext_dir("py") for this node's own
      # Python files, get_ext_dir("web/js") for install_js()'s source,
      # get_ext_dir("pysssss.default.json") for the bundled config
      # template), not just the one write (get_ext_dir("pysssss.json"),
      # the live config copy). Confirmed the hard way: an earlier
      # version of this patch redirected get_ext_dir() itself, which
      # broke every one of those reads ("Missing pysssss.default.json"
      # errors on a real run) -- only the specific config_path
      # assignment inside get_extension_config() is targeted instead.
      #
      # get_comfy_dir() -- os.path.dirname(inspect.getfile(
      # PromptServer)), comfyCore's own read-only Nix store path -- is
      # safe to redirect wholesale, since every one of its callers
      # (get_web_ext_dir(), used by install_js()) is a pure write with
      # nothing to read back from the original location.
      repo = "ComfyUI-Custom-Scripts";
      script = ''
        sed -i 's|config_path = get_ext_dir("pysssss\.json")|config_path = "${nodeDataDir "ComfyUI-Custom-Scripts"}/pysssss.json"|' \
          "$out/pysssss.py"
        sed -i 's|dir = os\.path\.dirname(inspect\.getfile(PromptServer))|dir = "${nodeDataDir "ComfyUI-Custom-Scripts"}"|' \
          "$out/pysssss.py"
      '';
    }

    {
      # NOT the same pysssss.py as Custom-Scripts, despite the identical
      # filename -- confirmed by actually reading both copies, not
      # assumed from the shared name. This node's version has no
      # default-template/copy mechanism at all: get_extension_config()
      # reads pysssss.user.json if present, else falls back to
      # pysssss.json directly -- and pysssss.json here is a real,
      # bundled, read-only resource file (this node's actual model
      # catalog, confirmed by reading it), not something ever written.
      # So get_ext_dir() needs no patching at all for this node -- only
      # get_comfy_dir() (comfyCore's path, used solely by install_js()'s
      # write-only web-extension symlink) does.
      repo = "ComfyUI-WD14-Tagger";
      script = ''
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
      #
      # A second real bug, only found by actually running this after
      # the redirect: once downloaded, usdu_patch.py does
      # `from repositories import ultimate_upscale as usdu` -- a
      # top-level (not relative) import, resolved via sys.path.
      # `sys.path.insert(0, repo_dir)` (below current_dir's assignment)
      # only adds the real, unredirected source dir -- before this
      # patch, that was fine because current_dir and repo_dir were the
      # same value, so `repositories/` sat right next to what was
      # already on sys.path. Redirecting current_dir alone broke that:
      # repositories/ now lives somewhere sys.path never points at.
      # Fixed by inserting current_dir onto sys.path too, right after
      # repo_dir's own insert.
      repo = "ComfyUI_UltimateSDUpscale";
      script = ''
        sed -i 's|^current_dir = os\.path\.dirname(os\.path\.realpath(__file__))|current_dir = "${nodeDataDir "ComfyUI_UltimateSDUpscale"}"|' \
          "$out/__init__.py"
        sed -i '/^sys\.path\.insert(0, repo_dir)$/a sys.path.insert(0, current_dir)' \
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

    {
      # inspire/prompt_support.py:35-36 -- pb_yaml_path (write target,
      # the live preset file) and pb_yaml_path_example (read-only
      # bundled template) are both built from the same resource_path
      # base. Same shape as the pysssss.py cases above: only the write
      # target is redirected, resource_path itself (and therefore
      # pb_yaml_path_example) stays pointed at the real, read-only
      # source. Caught internally (a bare except, not a crash) either
      # way -- this only fixes the resulting "prompt builder preset"
      # feature staying permanently empty, not a startup failure.
      repo = "ComfyUI-Inspire-Pack";
      script = ''
        sed -i "s|pb_yaml_path = os\\.path\\.join(resource_path, 'prompt-builder\\.yaml')|pb_yaml_path = \"${nodeDataDir "ComfyUI-Inspire-Pack"}/prompt-builder.yaml\"|" \
          "$out/inspire/prompt_support.py"
      '';
    }
  ];
}
