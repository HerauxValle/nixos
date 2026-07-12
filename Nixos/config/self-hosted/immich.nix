{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/immich/. Data only, same as every
# other service's config/self-hosted/<name>.nix.
{
  config.vars.selfHosted.immich = {
    enabled = true;

    # Off for now -- still exists, still systemctl start-able by hand,
    # just not pulled in on boot/rebuild. Matches every other migrated
    # service's real config on this machine right now.
    autoStart = false;

    # Real, existing data (43GB) -- confirmed genuine Immich internal
    # structure (upload/, library/, thumbs/, profile/, encoded-video/,
    # backups/, each with their own .immich marker), inside the "Media"
    # Casket vault (distinct from the "SelfHosted" vault every other
    # service uses), mounted at ~/Images/Media. Immich apparently ran
    # against this data at some point via a mechanism other than the old
    # bash framework's own install path (~/Applications/Networking/Immich
    # doesn't exist on disk at all) -- the raw files survived because
    # they were vault-backed, but the real Postgres database (accounts,
    # albums, face-recognition index) was never vault-backed the same way
    # (the old framework's own database.sh is explicit: Postgres/Redis
    # are plain system services, not vendored/backed up at all) and
    # backups/ itself is empty (just the .immich marker, no real .sql
    # dump ever completed) -- so this is a fresh Postgres database on
    # first start, pointed at real but currently-orphaned files (still
    # sharded under the old, now-nonexistent user's UUID directory).
    # Expect to re-add the actual photos through Immich's own external
    # library / re-upload flow rather than them "just appearing" -- the
    # bytes are real and worth keeping in place, the catalog isn't.
    mediaLocation = "${config.vars.homeDirectory}/Images/Media/Cloud";

    # The "Media" vault's own mountpoint -- immich-server's preStart
    # fails fast if this isn't mounted yet (cas Media open), same
    # mechanism as every other vault-backed service's requireMounts.
    requireMounts = [
      "${config.vars.homeDirectory}/Images/Media"
    ];

    # null = services.immich.host/.port's own defaults (localhost:2283)
    # apply untouched.
    host = null;
    port = null;

    # null -- nothing needs a secrets file yet (Postgres/Redis both use
    # their unix-socket defaults, no OAuth configured). See default.nix's
    # own CAUTION comment before ever setting this: services.immich's
    # secretsFile has no "-" missing-file fallback the way this
    # framework's own environmentFile convention does elsewhere -- only
    # set this once the real file already exists
    # (`secrets self-hosted immich`).
    environmentFile = null;

    enableMachineLearning = true;

    environment = { };
    machineLearningEnvironment = { };
  };
}
