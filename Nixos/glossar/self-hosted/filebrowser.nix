{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.selfHosted.filebrowser option, all
# commented out. Same shape as glossar/main/variables.nix, scoped to one
# service. Schema: modules/services/self-hosted/filebrowser/default.nix.
# Real values on this machine: config/self-hosted/filebrowser.nix. Full
# reference (systemd units, workflows, "why" for every mechanism below):
# modules/services/self-hosted/filebrowser/info.md.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste reference.
# Copy a block (or a line out of one) into config/self-hosted/filebrowser.nix
# and uncomment it there to actually set it. Terse, ini-style companion to
# that service's info.md -- regenerate by hand alongside it, nothing keeps
# either in sync automatically.
# =========================================================================

{
  # config.vars.selfHosted.filebrowser = {

  #   # --- master switch --------------------------------------------------
  #   # true = live service + actions exist and run. false = torn down
  #   # automatically on the next rebuild (see teardownPaths below), not
  #   # just absent.
  #   enabled = false;

  #   # --- plain base dir -- real data is at dataDir/<storage[0].src> ------
  #   # (the BoltDB -- users, settings). The binary itself comes from the
  #   # Nix-built package and never touches this directory.
  #   dataDir = "${homeDirectory}/Applications/Networking/FileBrowser";

  #   autoStart = true;  # false = exists, systemctl start-able, but not on boot/rebuild

  #   host = "127.0.0.1";  # passed as --address, also baked into the BoltDB on first init
  #   port = 8090;          # passed as --port, same two-places-it-lands as host

  #   # --- filesystem root served -- applied once via `config init`, only when the BoltDB doesn't exist yet --
  #   root = homeDirectory;

  #   # --- paired facts about the pinned release -- both required together --
  #   # nix-prefetch-url --type sha256 <url> | nix hash convert --to sri
  #   version = "2.63.18";
  #   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  #   # --- passthrough env for the live process -----------------------------
  #   environment = { };

  #   # --- vault-backed real data -- first entry is the real data location, load-bearing --
  #   storage = [
  #     { src = "data"; dest = "${homeDirectory}/Images/SelfHosted/FileBrowser"; }
  #   ];

  #   # --- must already be a mountpoint before this service (or its preStart) runs --
  #   requireMounts = [ "${homeDirectory}/Images/SelfHosted" ];

  #   # --- what enabled=false actually removes -------------------------------
  #   # Empty (the default) means "everything under dataDir except storage"
  #   # -- safe here since dataDir holds nothing but the storage symlink itself.
  #   teardownPaths = [ ];

  # };
}
