# &desc: "Per-node source patches that redirect hardcoded read-only write locations to writable node_data/<repo> subdirs under dataDir."

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
  dataDir = config.vars.services.selfHosted.comfyui.dataDir;
  nodeDataDir = repo: "${dataDir}/node_data/${repo}";
in
{
  config.vars.services.selfHosted.comfyui.nodePatches = [
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
      # get_comfy_dir() (comfyCore's path, used solely by install_js()'s
      # write-only web-extension symlink) needs the same redirect as
      # Custom-Scripts. get_ext_dir() itself still needs no patching --
      # but wd14tagger.py:38 has its own separate write, found only by
      # actually running this: when ComfyUI's own "wd14_tagger" model
      # folder isn't registered (the common case), it falls back to
      # `get_ext_dir("models", mkdir=True)` -- this node's own read-only
      # bind mount again, for where downloaded .onnx tagger models
      # would live. Redirected to nodeDataDir like every other write
      # target in this file.
      repo = "ComfyUI-WD14-Tagger";
      script = ''
        sed -i 's|dir = os\.path\.dirname(inspect\.getfile(PromptServer))|dir = "${nodeDataDir "ComfyUI-WD14-Tagger"}"|' \
          "$out/pysssss.py"
        sed -i 's|get_ext_dir("models", mkdir=True)|"${nodeDataDir "ComfyUI-WD14-Tagger"}/models"|' \
          "$out/wd14tagger.py"
      '';
      # Replacing get_ext_dir("models", mkdir=True) with a plain string
      # drops its mkdir=True behavior -- declared here instead so
      # preStart creates it, same as every other pre-created path in
      # this file.
      dirs = [ "models" ];
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
      # the redirect -- and initially misdiagnosed (see below):
      # repositories/__init__.py (a REAL file bundled in this node's own
      # repo, at repositories/__init__.py, not something the download
      # creates) independently computes its own
      # `repositories_path = os.path.dirname(os.path.realpath(__file__))`
      # and looks for repositories_path/ultimate_sd_upscale/scripts/
      # ultimate-upscale.py there. Since __file__ for that module always
      # resolves to wherever it was actually imported from (the
      # bind-mounted, unredirected source -- it's never copied anywhere
      # else), it keeps looking in the real source even after
      # current_dir (used only by __init__.py's own download logic) was
      # redirected -- so the downloaded content and this lookup end up
      # in two different places. Fixed by redirecting
      # repositories_path too, to the exact same nodeDataDir/repositories
      # the download actually writes to.
      #
      # (`from repositories import ultimate_upscale as usdu` in
      # usdu_patch.py resolves fine via the existing, unpatched
      # `sys.path.insert(0, repo_dir)` -- repositories/__init__.py itself
      # is real and bind-mounted, nothing extra needed on sys.path for
      # that part. An earlier version of this patch added a second
      # sys.path insert for current_dir here, which didn't address the
      # actual mismatch and has been removed.)
      repo = "ComfyUI_UltimateSDUpscale";
      script = ''
        sed -i 's|^current_dir = os\.path\.dirname(os\.path\.realpath(__file__))|current_dir = "${nodeDataDir "ComfyUI_UltimateSDUpscale"}"|' \
          "$out/__init__.py"
        sed -i 's|repositories_path = os\.path\.dirname(os\.path\.realpath(__file__))|repositories_path = "${nodeDataDir "ComfyUI_UltimateSDUpscale"}/repositories"|' \
          "$out/repositories/__init__.py"
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
      #
      # py/config.py:45 has a second, entirely independent computation
      # of the same conceptual "styles" location (FOOOCUS_STYLES_DIR =
      # Path(__file__).parent.parent / "styles") -- found only by
      # actually running this: __init__.py's own styles_path/os.mkdir
      # now correctly creates and populates the redirected nodeDataDir
      # location, but prompt.py's define_schema() reads from
      # FOOOCUS_STYLES_DIR instead, which still pointed at the real,
      # empty (nothing was ever created there) bind-mounted source.
      # Redirected to the exact same nodeDataDir/styles the other patch
      # already populates. RESOURCES_DIR, one line above, uses the same
      # Path(__file__).parent.parent base for a different, read-only
      # purpose -- the line-anchored match targets only
      # FOOOCUS_STYLES_DIR's own assignment, not that shared pattern.
      repo = "ComfyUI-Easy-Use";
      script = ''
        sed -i 's|os\.path\.dirname(__file__)|"${nodeDataDir "ComfyUI-Easy-Use"}"|g' \
          "$out/__init__.py"
        sed -i 's|^FOOOCUS_STYLES_DIR = os\.path\.join(Path(__file__)\.parent\.parent, "styles")|FOOOCUS_STYLES_DIR = "${nodeDataDir "ComfyUI-Easy-Use"}/styles"|' \
          "$out/py/config.py"
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

    {
      # No source patch at all -- unlike everything else in this file,
      # was-node-suite-comfyui already supports overriding its config
      # location via a WAS_CONFIG_DIR environment variable
      # (WAS_Node_Suite.py:156: `os.environ.get('WAS_CONFIG_DIR',
      # WAS_SUITE_ROOT)`, WAS_SUITE_ROOT being its own read-only bind
      # mount, the default). comfyui.nix sets that env var directly on
      # the live process instead of touching this node's source at all.
      # This entry exists purely for its dirs -- to get
      # node_data/was-node-suite-comfyui created in preStart, since
      # WAS_CONFIG_DIR points there and the directory has to actually
      # exist before WAS_Node_Suite.py tries to write its config file
      # into it.
      repo = "was-node-suite-comfyui";
    }
  ];
}
