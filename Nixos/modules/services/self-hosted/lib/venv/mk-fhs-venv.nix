# &desc: "FHS venv builder -- buildFHSEnv wrapper, pure+reproducible (symlinks not copies), extraBwrapArgs for bind-mount overrides."

{ pkgs }:

# A pure, reproducible sandbox for services whose dependencies need a
# real FHS layout (compiled Python wheels expecting /lib, /usr/lib --
# nothing about this derivation itself is impure, it's a symlink+
# bind-mount merge of targetPkgs, same as pkgs.symlinkJoin, not copies).
#
# extraBwrapArgs -- a real, existing buildFHSEnv option (confirmed via
# its own __functionArgs, not assumed) -- passes extra raw bwrap flags
# through. Exists here, generically, for any FHS-based service that
# needs to bind-mount something at a specific in-sandbox path rather
# than symlink it on the real filesystem. First real use:
# ComfyUI's custom_nodes/ (see comfyui/comfyui.nix) -- a plain
# filesystem symlink there meant `Path(__file__).resolve()` (a common
# pattern in node code trying to locate the ComfyUI root) followed the
# symlink through to the flat, unrelated Nix store path instead of the
# meaningful dataDir-relative one, breaking any node written assuming
# a normal git-clone-into-custom_nodes/ layout -- confirmed via two
# real crashes, not hypothetical. A bind mount isn't a symlink to the
# OS, so `.resolve()` has nothing to follow through -- fixes the whole
# class of bug generically, not per-node. Any future service hitting
# the same kind of "this needs to look like it's really at path X, not
# just symlinked to X" problem can reuse this the same way.
{ name, targetPkgs, extraBwrapArgs ? [ ] }:
pkgs.buildFHSEnv { name = "self-hosted-${name}-fhs"; inherit targetPkgs extraBwrapArgs; }
