# &desc: "Commented example reference for config.vars.services.selfHosted.stash -- copy/paste into config/self-hosted/stash.nix, companion to info.md."

{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.services.selfHosted.stash option, all commented
# out. Same shape as glossar/main/variables.nix, scoped to one service.
# Schema: modules/services/self-hosted/stash/default.nix. Real values on
# this machine: config/self-hosted/stash.nix. Full reference (systemd
# units, workflows, "why" for every mechanism below):
# modules/services/self-hosted/stash/info.md.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste reference.
# Copy a block (or a line out of one) into config/self-hosted/stash.nix
# and uncomment it there to actually set it. Terse, ini-style companion to
# that service's info.md -- regenerate by hand alongside it, nothing keeps
# either in sync automatically.
# =========================================================================

{
  # config.vars.services.selfHosted.stash = {

  #   # --- master switch --------------------------------------------------
  #   # true = live service + actions exist and run. false = torn down
  #   # automatically on the next rebuild (see teardownPaths below), not
  #   # just absent.
  #   enabled = false;

  #   # --- plain base dir -- real data is at dataDir/<storage[0].src> ------
  #   # (config.yml, database, thumbnails, cache, blobs). The binary itself
  #   # comes from the Nix-built package and never touches this directory.
  #   dataDir = "${homeDirectory}/Images/SelfHosted/Stash";

  #   autoStart = true;  # false = exists, systemctl start-able, but not on boot/rebuild

  #   host = "0.0.0.0";  # passed as --host
  #   port = 9999;        # passed as --port

  #   # --- paired facts about the pinned release -- both required together --
  #   version = "0.31.1";
  #   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  #   # --- passthrough env for the live process -----------------------------
  #   environment = { };

  #   # --- vault-backed real data -- first entry is the real data location, load-bearing --
  #   storage = [
  #     { src = "data"; dest = "${homeDirectory}/Images/SelfHosted/Stash"; }
  #   ];

  #   # --- must already be a mountpoint before this service (or its preStart) runs --
  #   requireMounts = [ "${homeDirectory}/Images/SelfHosted" ];

  #   # --- what enabled=false actually removes -------------------------------
  #   # Empty (the default) means "everything under dataDir except storage"
  #   # -- safe here since dataDir holds nothing but the storage symlink itself.
  #   teardownPaths = [ ];

  # };
}
