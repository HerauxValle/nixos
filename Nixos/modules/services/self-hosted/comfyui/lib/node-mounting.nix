{ lib, pkgs, dataDir, activeNodes, nodePatches }:

# Node source fetch + per-node patches (see nodePatches -- a real Nix
# option, config/self-hosted/comfyui/patches.nix's data, not hardcoded
# here), plus the bind-mount plumbing that makes custom_nodes/<repo>
# look like a real, writable-looking location instead of a flat Nix
# store path. Split out of comfyui.nix once that file grew past ~480
# lines -- node mounting is a self-contained concern (nothing outside
# this file needs mkNodeSrc/nodeBindArgs except requirements.nix, which
# takes them as explicit inputs) and info.md's "Node mounting" section
# documents this exact behavior.

let
  # nodePatches arrives as the raw listOf{repo,script,dirs} from cfg --
  # turn it into a repo -> script lookup once, here, rather than
  # re-searching the list for every node in activeNodes. dirs isn't
  # used here at all -- it only affects preStart's mkdir generation
  # (comfyui.nix), never the source derivation itself.
  scriptsByRepo = lib.listToAttrs
    (map (p: lib.nameValuePair p.repo p.script) nodePatches);

  mkNodeSrc = node:
    let
      base = pkgs.fetchFromGitHub { inherit (node) owner repo rev hash; };
      script = scriptsByRepo.${node.repo} or "";
    in
    if script != "" then
      pkgs.runCommand "node-${node.repo}-patched" { } ''
        cp -r ${base} $out
        chmod -R u+w $out
        ${script}
      ''
    else
      base;

  # Bind-mounted, not symlinked -- see ../../self-hosted.nix's mkFHSVenv
  # comment for the full reasoning. In short: a plain `ln -sfn` here
  # meant any node computing its own location via
  # `Path(__file__).resolve()` (a common pattern for "find the ComfyUI
  # root") saw the real, flat Nix store path instead of the meaningful
  # dataDir/custom_nodes/<repo> one, breaking on two real nodes
  # (ComfyUI-SAM3, ComfyUI-SAM3DBody) confirmed via actual crashes. A
  # bind mount isn't a symlink to the OS -- .resolve() has nothing to
  # follow through, so this fixes the whole class of bug, not just
  # those two, with no per-node patch needed.
  nodeBindArgs = lib.concatMap
    (node: [ "--ro-bind" "${mkNodeSrc node}" "${dataDir}/custom_nodes/${node.repo}" ])
    activeNodes;

  # bwrap binds *through* the real /home (not a synthetic root section),
  # so every mount point in nodeBindArgs has to already exist as a real
  # directory on the actual host filesystem before the sandbox launches
  # -- confirmed directly (bwrap fails with "No such file or directory"
  # otherwise, and separately, mkdir -p is a no-op over a leftover
  # symlink from the old design, it doesn't replace it -- both caught by
  # actually running this, not assumed). Also removes any leftover
  # directory for a node no longer in installed.nodes, generic
  # reconciliation against real (always-empty-on-the-host) placeholder
  # dirs, not against node content -- the actual source only ever
  # appears inside the sandbox's own mount namespace, never written to
  # the host.
  prepareNodeMountsScript = ''
    set -euo pipefail
    mkdir -p "${dataDir}/custom_nodes"
    declared_nodes="${lib.concatStringsSep " " (map (n: n.repo) activeNodes)}"
    for node in $declared_nodes; do
      [ -L "${dataDir}/custom_nodes/$node" ] && rm -f "${dataDir}/custom_nodes/$node"
      mkdir -p "${dataDir}/custom_nodes/$node"
    done
    for entry in "${dataDir}"/custom_nodes/*; do
      [ -e "$entry" ] || continue
      name="$(basename "$entry")"
      keep=0
      for d in $declared_nodes; do
        [ "$d" = "$name" ] && { keep=1; break; }
      done
      [ "$keep" = 1 ] || rm -rf "$entry"
    done
  '';
in
{
  inherit mkNodeSrc nodeBindArgs prepareNodeMountsScript;
}
