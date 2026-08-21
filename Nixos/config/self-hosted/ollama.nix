# &desc: "Ollama service config -- enabled/dataDir/autoStart=false, storage symlinks for model relocation."

{ config, ... }:

# Real values -- schema + the actual behavior live in
# ../../modules/services/self-hosted/ollama/. This file only ever holds
# data (what you want), never logic (what to do with it) -- same split as
# config/scripts.nix vs its module. Everything the module would otherwise
# quietly default is spelled out explicitly here on purpose, so the whole
# picture is visible in one place instead of split between here and the
# module's own defaults.
{
  config.vars.services.selfHosted.ollama = {
    # true = installed: systemd units exist, postStart's model sync runs.
    # false = torn down on the next rebuild -- dataDir (pulled model
    # blobs) removed automatically; storage (empty by default here) is
    # never touched by that teardown.
    enabled = true;

    dataDir = "${config.vars.identity.homeDirectory}/Applications/Networking/Ollama";

    # Off for now -- still exists, still systemctl start-able by hand,
    # just not pulled in on boot/rebuild.
    autoStart = false;

    # Relocate a subpath of dataDir elsewhere -- each entry becomes a
    # forced symlink (systemd.tmpfiles.rules' `L+`), applied at every
    # activation: `dataDir/<src>` -> `<dest>`. `src` is relative to
    # dataDir, `dest` is an absolute path that gets created if missing.
    # Example, to put models on a bigger drive instead of dataDir's own
    # disk:
    #   storage = [
    #     { src = "models"; dest = "/mnt/bigdrive/ollama-models"; }
    #   ];
    # None needed right now -- models/logs stay under dataDir as-is.
    storage = [ ];

    # Empty -- dataDir holds nothing but pulled model blobs, so the
    # default "everything but storage" teardown (when enabled = false)
    # is safe as-is; no need to scope it down further.
    teardownPaths = [ ];

    # Update together -- see
    # ../../modules/services/self-hosted/ollama/default.nix for how to
    # get a new hash when bumping version.
    version = "0.31.2";
    hash = "sha256-LIjw8xqVm6xaPK1MxSluxWhVHUqnn1SPVUrbK1dbMTM=";

    environment = {
      OLLAMA_HOST = "0.0.0.0:11434";
      OLLAMA_ORIGINS = "*";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_CONTEXT_LENGTH = "8192";
      OLLAMA_NUM_PARALLEL = "2";
      OLLAMA_KEEP_ALIVE = "5m";
      CUDA_VISIBLE_DEVICES = "0";
    };

    # null = no override -- the OLLAMA_HOST line above already sets both
    # halves directly, same as before these two options existed. Only
    # set either of these if you want a typed override to win over the
    # line above instead of hand-editing it.
    host = null;
    port = null;

    models = [
      # CHAT / GENERAL
      "gpt-oss:20b"
      # "deepseek-r1:14b"
      # "dolphin3:8b-llama3.1-q8_0"
      # "glm-4.7-flash:q4_K_M"
      # "llama3.1:8b"

      # CODE
      # "codellama:13b"
      # "deepseek-coder-v2:16b"
      # "qwen2.5-coder:14b"
      # "qwen3-coder:30b"
      # "devstral:24b"
      # "rnj-1:8b"
      # "lfm2:24b"

      # EMBEDDING (used by Open WebUI RAG)
      # "nomic-embed-text"

      # UNCENSORED
      "ikiru/dolphin-mistral-24b-venice-edition:latest"
      # "mdhm_hmmd/gemma4-e4b-uncensored-q8:latest"
      # "baytout3/Gemma-4-Uncensored-HauhauCS-Aggressive:e4b"
      # "fredrezones55/Gemma-4-Uncensored-HauhauCS-Aggressive:e4b"
      # "llama2-uncensored:7b"
      "baytout3/gemma4-12b-qat-uncensored-hauhaucs-balanced:q4_k_m"

      # GEMMA FAMILY
      # "gemma4:26b-a4b-it-q4_K_M"
      # "gemma4:e4b"
      # "translategemma:4b"
      # "translategemma:12b"
      # "functiongemma:270m"
      # "embeddinggemma:300m"

      # QWEN FAMILY
      "qwen3.5:0.8b"
      # "qwen3.5:2b"
      # "qwen3.5:4b"
      # "qwen3.5:9b"
      # "qwen3.5:27b"
      # "qwen3-vl:8b-thinking-q4_K_M"
      # "qwen3-vl:8b-thinking-q8_0"
      # "qwen3-vl:2b-thinking"
      # "fredrezones55/Qwen3.5-Uncensored-HauhauCS-Aggressive:4b"
      "fredrezones55/Qwen3.5-Uncensored-HauhauCS-Aggressive:9b"

      # VISION
      # "llava:13b"
      # "deepseek-ocr:3b"
    ];
  };
}
