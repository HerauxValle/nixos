{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/openwebui/. Data only, same as
# ollama.nix/stash.nix.
{
  config.vars.services.selfHosted.openwebui = {
    # true = installed: systemd units exist, preStart's venv install
    # runs. false = torn down on the next rebuild -- venvDir and dataDir
    # (minus the "data" storage entry) removed automatically; the real
    # chat/user data inside the vault is never touched by that teardown.
    enabled = true;

    dataDir = "${config.vars.identity.homeDirectory}/Applications/Networking/OpenWebUI";

    # Off for now -- still exists, still systemctl start-able by hand,
    # just not pulled in on boot/rebuild.
    autoStart = false;

    host = "0.0.0.0";
    port = 8080;

    # The one real data location -- inside the SelfHosted Casket vault,
    # same one Stash uses. Confirmed correct (not the "Vaults" vault the
    # old obsidian-unlock.sh hook referenced -- that was stale).
    storage = [
      { src = "data"; dest = "${config.vars.identity.homeDirectory}/Images/SelfHosted/OpenWebUI"; }
    ];

    # Independent fact, not derived from storage above.
    requireMounts = [ "${config.vars.identity.homeDirectory}/Images/SelfHosted" ];

    # Empty -- dataDir holds nothing but the storage symlink itself, so
    # the default "everything but storage" teardown (when enabled =
    # false) is safe as-is; no need to scope it down further.
    teardownPaths = [ ];

    environment = {
      OLLAMA_BASE_URL = "http://localhost:11434";
      OPENAI_API_KEY = "";
      OPENAI_API_BASE_URL = "";
      ENABLE_API_KEYS = "True";
      USER_PERMISSIONS_FEATURES_API_KEYS = "True";
      ENABLE_FORWARD_USER_INFO_HEADERS = "True";

      # Auth
      ENABLE_SIGNUP = "true";
      ENABLE_LOGIN_FORM = "true";
      DEFAULT_USER_ROLE = "pending";

      # RAG -- use Ollama for embeddings (avoids auto-downloading HF models)
      RAG_EMBEDDING_ENGINE = "ollama";
      RAG_EMBEDDING_MODEL = "nomic-embed-text";
      RAG_EMBEDDING_MODEL_AUTO_UPDATE = "false";
      RAG_RERANKING_MODEL_AUTO_UPDATE = "false";
      WHISPER_MODEL_AUTO_UPDATE = "false";

      # Features
      ENABLE_CHANNELS = "false";
      ENABLE_MEMORIES = "true";
      ENABLE_CODE_INTERPRETER = "false";
      ENABLE_IMAGE_GENERATION = "false";
      ENABLE_WEB_SEARCH = "false";
    };
  };
}
