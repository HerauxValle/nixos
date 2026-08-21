[main]:[
  [meta]:[
    sdc_version = 1
    name        = ollama
    author      = herauxvalle
  ]:
  [services]:[
    ollama
  ]:
  [startup]:[
    ollama
  ]:
]:

[ollama]:[

  [env]:[
    OLLAMA_HOST   = 0.0.0.0
    OLLAMA_MODELS = /models
  ]:

  [build]:[
    [general]:[
      rootfs = ubuntu:22.04
      [deps]:[
        pkg: curl ca-certificates zstd
      ]:
    ]:
    [install]:[
      curl -fsSL https://ollama.com/install.sh | sh
    ]:
  ]:

  [run]:[
    [config]:[
      entrypoint = /usr/local/bin/ollama serve
      port       = 11434:11434
      restart    = on-failure
    ]:
    [storage]:[
      models = /models
      logs   = /var/log/ollama
    ]:
  ]:

]: