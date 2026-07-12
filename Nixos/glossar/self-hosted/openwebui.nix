{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.selfHosted.openwebui option, all commented
# out. Same shape as glossar/main/variables.nix, scoped to one service.
# Schema: modules/services/self-hosted/openwebui/default.nix. Real values
# on this machine: config/self-hosted/openwebui.nix. Full reference
# (systemd units, workflows, "why" for every mechanism below):
# modules/services/self-hosted/openwebui/info.md.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste reference.
# Copy a block (or a line out of one) into config/self-hosted/openwebui.nix
# and uncomment it there to actually set it. Terse, ini-style companion to
# that service's info.md -- regenerate by hand alongside it, nothing keeps
# either in sync automatically.
# =========================================================================

{
  # config.vars.selfHosted.openwebui = {

  #   # --- master switch --------------------------------------------------
  #   # true = live service + actions exist and run. false = torn down
  #   # automatically on the next rebuild (venv + dataDir minus storage --
  #   # see teardownPaths below), not just absent.
  #   enabled = false;

  #   # --- plain, always-available -- real data is at dataDir/<storage[0].src> --
  #   dataDir = "${homeDirectory}/Applications/Networking/OpenWebUI";

  #   # --- disposable, regenerated automatically whenever requirementsLock's hash changes --
  #   venvDir = "${homeDirectory}/.impure/python-venvs/self-hosted/openwebui";

  #   autoStart = true;  # false = exists, systemctl start-able, but not on boot/rebuild

  #   host = "0.0.0.0";  # passed as --host
  #   port = 8080;       # passed as --port

  #   # --- passthrough env for the live process -----------------------------
  #   environment = {
  #     OLLAMA_BASE_URL = "http://localhost:11434";
  #     ENABLE_SIGNUP = "true";
  #   };

  #   # --- vault-backed real data -- first entry is the real data location --
  #   storage = [
  #     { src = "data"; dest = "${homeDirectory}/Images/SelfHosted/OpenWebUI"; }
  #   ];

  #   # --- must already be a mountpoint before this service (or its preStart) runs --
  #   requireMounts = [ "${homeDirectory}/Images/SelfHosted" ];

  #   # --- what enabled=false actually removes -------------------------------
  #   # Empty (the default) means "everything under dataDir except storage"
  #   # -- safe here since dataDir holds nothing but the storage symlink itself.
  #   teardownPaths = [ ];

  # };
}
