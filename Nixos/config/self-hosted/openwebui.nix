# &desc: "OpenWebUI service config -- enabled/venvDir/dataDir/autoStart=false, chat/user data in SelfHosted vault."

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

    # See searxng.nix's own afterUnits comment for the full story.
    afterUnits = [ "autostart@selfHosted.service" ];

    # Empty -- dataDir holds nothing but the storage symlink itself, so
    # the default "everything but storage" teardown (when enabled =
    # false) is safe as-is; no need to scope it down further.
    teardownPaths = [ ];

    environment = {
      OLLAMA_BASE_URL = "http://localhost:11434";

      # Title/tags/autocomplete default to whatever model the active chat
      # uses. Ollama hard-caps multimodal models (mmproj/vision baked into
      # the GGUF, e.g. all Qwen3.5 tags here) to n_slots=1 regardless of
      # OLLAMA_NUM_PARALLEL -- confirmed via logs, not VRAM-driven, no env
      # var lifts it. So every title/tag/autocomplete call shared the
      # chat model's one slot and blew away its prompt-cache checkpoint,
      # forcing a full reprocess on the next message. Pointing these at a
      # separate model gives them their own independent slot pool --
      # doesn't matter that this one is also multimodal, since separate
      # models never share slots with each other.
      TASK_MODEL = "qwen3.5:0.8b";
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
