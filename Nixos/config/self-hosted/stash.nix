{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/stash/. Data only, same as ollama.nix.
{
  config.vars.selfHosted.stash = {
    dataDir = "${config.vars.homeDirectory}/Images/SelfHosted/Stash";

    autoStart = true;

    host = "0.0.0.0";
    port = 9999;

    # Update together -- see
    # ../../modules/services/self-hosted/stash/default.nix for how to
    # get a new hash when bumping version.
    version = "0.31.1";
    hash = "sha256-X3E5Grx866/VuS97MlCWJzDIvj5/EvI/2YAph4slaMA=";

    environment = { };

    # No relocations -- generated/cache/etc stay under dataDir as-is.
    storage = [ ];
  };
}
