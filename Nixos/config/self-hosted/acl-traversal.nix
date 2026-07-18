
{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/lib/acl-traversal/. Data only, same
# split as every other service's config/self-hosted/<name>.nix -- this
# one just isn't scoped to a single service, it's real per-machine
# permission facts (see that module's own default.nix for exactly when
# to add an entry here).
{
  config.vars.services.selfHosted.aclTraversal = [
    # Example entry, kept as documentation -- no longer live now that
    # qbittorrent's paths.save/temp/export/finished moved off
    # /run/media/<user> (0750 root:root, which is what this grant
    # existed for) onto config.vars.system.mountpoints.device.storage.path
    # instead (/home/${config.vars.identity.username}/Drives/Storage). Real
    # history: /run/media/<user> blocked the dedicated qbittorrent
    # system user from ever reaching paths underneath it, completely
    # independent of whether Storage itself was mounted. Confirmed via
    # `sudo systemd-run --property=User=qbittorrent -- mountpoint -q
    # /run/media/herauxvalle/Storage` failing while the identical
    # command as root succeeded.
    # {
    #   unit = "qbittorrent";
    #   user = "qbittorrent";
    #   baseDir = "/run/media";
    #   path = "/run/media/${config.vars.identity.username}/Storage";
    # }
  ];
}
