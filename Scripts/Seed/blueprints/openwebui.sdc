[main]:[
  [meta]:[
    sdc_version = 1
    name        = openwebui
    author      = herauxvalle
  ]:
  [services]:[
    openwebui
  ]:
  [startup]:[
    openwebui
  ]:
]:

[openwebui]:[

  [env]:[
    OLLAMA_BASE_URL  = http://localhost:11434
    WEBUI_SECRET_KEY = changeme
    PORT             = 3000
  ]:

  [build]:[
    [general]:[
      rootfs = ubuntu:22.04
      [deps]:[
        pkg: python3 python3-pip curl ca-certificates
      ]:
    ]:
    [install]:[
      pip3 install open-webui
    ]:
  ]:

  [run]:[
    [config]:[
      entrypoint = open-webui serve
      port       = 3000:3000
      restart    = on-failure
    ]:
    [storage]:[
      data = /root/.local/share/open-webui
    ]:
  ]:

]:
