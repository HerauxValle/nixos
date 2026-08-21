# &desc: "Commented example reference for config.vars.services.selfHosted.odysseus (no dataDir, storage symlinked to srcDir) -- companion to info.md."

{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.services.selfHosted.odysseus option, all commented
# out. Same shape as glossar/main/variables.nix, scoped to one service.
# Schema: modules/services/self-hosted/odysseus/default.nix. Real values
# on this machine: config/self-hosted/odysseus.nix. Full reference
# (systemd units, workflows, "why" for every mechanism below):
# modules/services/self-hosted/odysseus/info.md.
#
# Odysseus (github.com/pewdiepie-archdaemon/odysseus) has no dataDir --
# unlike every other service here except Immich, its real vault-backed
# data gets symlinked directly into srcDir (see storage below).
#
# NOT imported anywhere -- never evaluated, purely a copy-paste reference.
# Copy a block (or a line out of one) into config/self-hosted/odysseus.nix
# and uncomment it there to actually set it. Terse, ini-style companion to
# that service's info.md -- regenerate by hand alongside it, nothing keeps
# either in sync automatically.
# =========================================================================

{
  # config.vars.services.selfHosted.odysseus = {

  #   # --- master switch --------------------------------------------------
  #   # true = live service + actions exist and run. false = venvDir torn
  #   # down on the next rebuild (srcDir isn't -- same already-accepted
  #   # limitation as SearXNG's own srcDir). storage-backed real data is
  #   # never touched either way.
  #   enabled = false;

  #   autoStart = true;  # false = exists, systemctl start-able, but not on boot/rebuild

  #   # --- bind address/port -- always explicit, uvicorn CLI flags -----------
  #   # no "leave as-is" mechanism the way SearXNG's settings.yml has.
  #   host = "0.0.0.0";
  #   port = 7000;

  #   # --- plain passthrough, on top of the real .env's own load_dotenv() --
  #   environment = {
  #     # anything not already in the real .env (see storage below)
  #   };

  #   # --- real vault data, symlinked directly into srcDir ------------------
  #   # (not a dataDir -- Odysseus's own app code computes these relative to
  #   # wherever it's actually running from, no env-var override exists)
  #   storage = [
  #     { src = "data"; dest = "${homeDirectory}/Images/SelfHosted/Odysseus/data"; }
  #     { src = "logs"; dest = "${homeDirectory}/Images/SelfHosted/Odysseus/logs"; }
  #     { src = ".env"; dest = "${homeDirectory}/Images/SelfHosted/Odysseus/.env"; }
  #   ];

  #   # --- must already be a mountpoint before this service (or its preStart) runs --
  #   requireMounts = [ "${homeDirectory}/Images/SelfHosted" ];

  #   # --- pinned git rev -- preStart clones/checks it out every start -------
  #   coreRev = "c075abce5dd21b1e7f701164e2aa9a48da6d09ea";

  # };
}
