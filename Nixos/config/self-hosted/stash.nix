
{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/stash/. Data only, same as ollama.nix.
{
  config.vars.services.selfHosted.stash = {
    # true = installed: systemd units exist. false = torn down on the
    # next rebuild -- dataDir (minus the "data" storage entry) removed
    # automatically; the real database/metadata/blobs inside the vault
    # are never touched by that teardown.
    enabled = true;

    # Plain, always-available -- holds nothing on its own (the binary is
    # Nix-built), it's just where the storage symlink below lands.
    dataDir = "${config.vars.identity.homeDirectory}/Applications/Networking/Stash";

    # Off for now -- still exists, still systemctl start-able by hand,
    # just not pulled in on boot/rebuild.
    autoStart = false;

    host = "0.0.0.0";
    port = 9999;

    # Update together -- see
    # ../../modules/services/self-hosted/stash/default.nix for how to
    # get a new hash when bumping version.
    version = "0.31.1";
    hash = "sha256-X3E5Grx866/VuS97MlCWJzDIvj5/EvI/2YAph4slaMA=";

    environment = { };

    # The one real data location -- inside the SelfHosted Casket vault.
    # dataDir/data -> this, so Stash's actual config/db/media metadata
    # live vault-protected while dataDir itself stays a plain path.
    storage = [
      { src = "data"; dest = "${config.vars.identity.homeDirectory}/Images/SelfHosted/Stash"; }
    ];

    # Independent fact, not derived from storage above -- they happen to
    # agree because this is the vault storage points into, not because
    # one is computed from the other. The second entry is a real,
    # separate drive Stash's own library paths (config.yml's "stash:"
    # section, outside Nix's control) point into -- confirmed missing on
    # a real run: scans silently completed against an empty/nonexistent
    # path, with no error, just nothing to show for it. Mounted via
    # config.vars.system.mountpoints (modules/system/mountpoints/) at
    # /home/${config.vars.identity.username}/Drives/Storage now, not the old
    # udisks2-managed /run/media/<user>/Storage.
    requireMounts = [
      "${config.vars.identity.homeDirectory}/Images/SelfHosted"
      config.vars.system.mountpoints.device.storage.path
    ];

    # Empty -- dataDir holds nothing but the storage symlink itself, so
    # the default "everything but storage" teardown (when enabled =
    # false) is safe as-is; no need to scope it down further.
    teardownPaths = [ ];
  };
}
