{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/lib/acl-traversal/. Data only, same
# split as every other service's config/self-hosted/<name>.nix -- this
# one just isn't scoped to a single service, it's real per-machine
# permission facts (see that module's own default.nix for exactly when
# to add an entry here).
{
  config.vars.selfHosted.aclTraversal = [
    # /run/media/<user> is 0750 root:root (confirmed via `stat`) --
    # blocks the dedicated qbittorrent system user from ever reaching
    # paths.save/temp/export/finished underneath it, completely
    # independent of whether Storage itself is mounted. Confirmed via
    # `sudo systemd-run --property=User=qbittorrent -- mountpoint -q
    # /run/media/herauxvalle/Storage` failing while the identical
    # command as root succeeded.
    {
      unit = "qbittorrent";
      user = "qbittorrent";
      baseDir = "/run/media";
      path = "/run/media/${config.vars.username}/Storage";
    }
  ];
}
