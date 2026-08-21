# &desc: "Odysseus service config -- enabled/autoStart=false, host/port from old main.sh and upstream defaults."

{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/odysseus/. Data only, same as every
# other service's config/self-hosted/<name>.nix.
{
  config.vars.services.selfHosted.odysseus = {
    enabled = true;

    # Off for now -- still exists, still systemctl start-able by hand,
    # just not pulled in on boot/rebuild. Matches every other migrated
    # service's real config on this machine right now.
    autoStart = false;

    # Real values the old main.sh already used on this machine (HOST=
    # "0.0.0.0", PORT="7000") -- also upstream's own real default.
    host = "0.0.0.0";
    port = 7000;

    environment = { };

    # config/data/logs/.env -- data/logs/.env real, recovered from a
    # previous real install already sitting in the SelfHosted vault
    # (~/Images/SelfHosted/Odysseus/, 89MB, including an already-set-up
    # admin account -- confirmed by inspecting it directly). Symlinked
    # straight into srcDir by odysseus.nix's own dataLinkScript, not a
    # dataDir (this service has none -- see default.nix's own top
    # comment for why).
    storage = [
      { src = "data"; dest = "${config.vars.identity.homeDirectory}/Images/SelfHosted/Odysseus/data"; }
      { src = "logs"; dest = "${config.vars.identity.homeDirectory}/Images/SelfHosted/Odysseus/logs"; }
      { src = ".env"; dest = "${config.vars.identity.homeDirectory}/Images/SelfHosted/Odysseus/.env"; }
    ];

    requireMounts = [
      "${config.vars.identity.homeDirectory}/Images/SelfHosted"
    ];

    # The exact commit the vault's already-recovered checkout was
    # actually sitting at (`git -C ~/Images/SelfHosted/Odysseus
    # rev-parse HEAD`, confirmed clean -- no uncommitted changes) --
    # pins to what's actually been running and is known to work with
    # the recovered real data, not just "whatever HEAD happens to be
    # today upstream".
    coreRev = "c075abce5dd21b1e7f701164e2aa9a48da6d09ea";
  };
}
