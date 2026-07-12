{ config, pkgs, ... }:

# Real per-node source patches -- split out from comfyui.nix purely for
# size/clarity, same convention as nodes.nix/models.nix. Deliberately
# takes `pkgs` (unlike nodes.nix/models.nix, which are pure data with no
# package references) -- a patch's fix sometimes has to point at a real
# package path (the font fix below points at pkgs.dejavu_fonts). A
# narrow, intentional exception to this directory's usual "never pkgs"
# rule for exactly this reason, not a general license to add logic here.
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
  ];
}
