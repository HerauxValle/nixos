{ selfHosted, requirementsIn, requirementsLock, requirementsLockPath, apply ? false }:

# Thin wrapper around ../../self-hosted.nix's mkDepsUpdateScript --
# OpenWebUI has nothing else to check for updates (no nodes, no models,
# no separate core revision), so this is the entire update surface.

selfHosted.mkDepsUpdateScript {
  serviceName = "openwebui";
  inherit requirementsIn requirementsLock requirementsLockPath apply;
}
