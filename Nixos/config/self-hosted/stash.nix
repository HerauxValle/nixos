{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/stash/. Data only, same as ollama.nix.
{
  config.vars.selfHosted.stash = {
    # Plain, always-available -- holds nothing on its own (the binary is
    # Nix-built), it's just where the storage symlink below lands.
    dataDir = "${config.vars.homeDirectory}/Applications/Networking/Stash";

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
      { src = "data"; dest = "${config.vars.homeDirectory}/Images/SelfHosted/Stash"; }
    ];

    # Independent fact, not derived from storage above -- they happen to
    # agree because this is the vault storage points into, not because
    # one is computed from the other.
    requireMounts = [ "${config.vars.homeDirectory}/Images/SelfHosted" ];
  };
}
