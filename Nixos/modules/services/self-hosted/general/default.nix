{ lib, ... }:

# Schema only -- logic lives in ./general.nix. Not one service's own
# module the way every other subfolder here is -- a shared surface for
# concerns that are genuinely machine-level, not any single service's
# own data, the first (and so far only) being ACL traversal grants (see
# ../lib/acl-traversal.nix for the actual mechanism and why it exists).
#
# Deliberately a flat array here rather than each service declaring its
# own `aclTraversalPaths`-shaped option: which dedicated system user can
# traverse which restrictive ancestor directory is a fact about *this
# machine's* real permission layout, not about any one service's config
# -- if a second service ever needs a grant into the same ancestor
# (e.g. another dedicated-user service also reading from
# /run/media/<user>), it belongs as one more entry in the same array,
# not a second, independently-declared copy of the same real grant.
{
  imports = [ ./general.nix ];

  options.vars.selfHosted.aclTraversal = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        unit = lib.mkOption {
          type = lib.types.str;
          description = "systemd unit name (e.g. \"qbittorrent\") whose own preStart this grant's script gets appended to.";
        };
        user = lib.mkOption {
          type = lib.types.str;
          description = "The dedicated system user needing traversal rights.";
        };
        baseDir = lib.mkOption {
          type = lib.types.str;
          description = "Nearest already-traversable-by-everyone ancestor to start walking from -- confirm with `stat -c %a <dir>` before picking one; walking further up than necessary just adds no-op ACL entries on directories that never needed one.";
        };
        path = lib.mkOption {
          type = lib.types.str;
          description = "The real path the dedicated user needs to reach -- every directory strictly between baseDir and this gets the ACL grant, not this path itself.";
        };
      };
    });
    default = [ ];
    description = ''
      Real, machine-level ACL traversal grants -- each entry gives one
      dedicated system user execute-only traversal into one restrictive
      ancestor directory it doesn't own, re-applied every time `unit`
      starts (not just once per rebuild -- see general.nix's own
      comment for why).

      WHEN TO ADD AN ENTRY: ProtectHome="tmpfs"+BindPaths (wired
      per-service, directly on whichever unit needs it) already solves
      this for *anything under /home* -- never add a /home-rooted path
      here, it doesn't need it. Add an entry here only when a real check
      confirms a dedicated (non-`config.vars.username`) system user
      genuinely can't reach a *non*-/home path:

        sudo systemd-run --property=User=<user> -- mountpoint -q <path>

      If that fails while the identical command as root succeeds, the
      blocking ancestor is too restrictively permissioned for that user
      to walk through on its own -- confirmed real case on this machine:
      /run/media/<user> is 0750 root:root, which blocks any dedicated-
      user service from ever reaching a path underneath it, completely
      independent of whether the drive itself is mounted.
    '';
  };
}
