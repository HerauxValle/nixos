{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.selfHosted.ollama option, all commented
# out. Same shape as glossar/main/variables.nix, scoped to one service.
# Schema: modules/services/self-hosted/ollama/default.nix. Real values on
# this machine: config/self-hosted/ollama.nix. Full reference (systemd
# units, workflows, "why" for every mechanism below):
# modules/services/self-hosted/ollama/info.md.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste reference.
# Copy a block (or a line out of one) into config/self-hosted/ollama.nix
# and uncomment it there to actually set it. Terse, ini-style companion to
# that service's info.md -- regenerate by hand alongside it, nothing keeps
# either in sync automatically.
# =========================================================================

{
  # config.vars.selfHosted.ollama = {

  #   # --- master switch --------------------------------------------------
  #   # true = live service + actions exist and run. false = torn down
  #   # automatically on the next rebuild (see teardownPaths below), not
  #   # just absent.
  #   enabled = false;

  #   # --- where pulled model blobs live -- drives OLLAMA_MODELS ----------
  #   dataDir = "${homeDirectory}/Applications/Networking/Ollama";

  #   autoStart = true;  # false = exists, systemctl start-able, but not on boot/rebuild

  #   # --- paired facts about the pinned release -- both required together --
  #   # nix-prefetch-url --type sha256 <url> | nix hash convert --to sri
  #   version = "0.31.2";
  #   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

  #   # --- plain passthrough to the live process and the sync unit ---------
  #   # OLLAMA_HOST can be set here directly, or via host/port below.
  #   environment = {
  #     OLLAMA_HOST = "0.0.0.0:11434";
  #     OLLAMA_CONTEXT_LENGTH = "8192";
  #     OLLAMA_KEEP_ALIVE = "5m";
  #     CUDA_VISIBLE_DEVICES = "0";
  #   };

  #   # --- optional typed override, wins over environment.OLLAMA_HOST if set --
  #   # null (default) = no override, environment.OLLAMA_HOST above applies as-is.
  #   host = null;
  #   port = null;

  #   # --- declared models -- reconciled automatically every start via postStart --
  #   models = [
  #     "llama3.1:8b"
  #     "qwen2.5-coder:14b"
  #   ];

  #   # --- vault-backed real data -- symlinked at rebuild time (usually empty for Ollama) --
  #   storage = [
  #     { src = "models"; dest = "/mnt/bigdrive/ollama-models"; }
  #   ];

  #   # --- what enabled=false actually removes -------------------------------
  #   # Empty (the default) means "everything under dataDir except storage"
  #   # -- safe here since dataDir holds nothing but pulled model blobs.
  #   teardownPaths = [ ];

  # };
}
