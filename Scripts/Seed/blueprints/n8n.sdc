[main]:[
  [meta]:[
    sdc_version = 1
    name        = n8n
    author      = herauxvalle
  ]:
  [services]:[
    n8n
  ]:
  [startup]:[
    n8n
  ]:
]:

[n8n]:[

  [env]:[
    NODE_ENV = production
    WEBHOOK_URL = http://localhost:5678
    N8N_DIAGNOSTICS_ENABLED = false
    N8N_ANALYTICS_EVENTS_ENABLED = false
  ]:

  [build]:[
    [general]:[
      rootfs = ubuntu:22.04
      [deps]:[
        pkg: curl ca-certificates
      ]:
    ]:
    [install]:[
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
      apt-get install -y nodejs
      npm install -g n8n
    ]:
  ]:

  [run]:[
    [config]:[
      entrypoint = n8n start
      port       = 5678:5678
      restart    = on-failure
    ]:
    [storage]:[
      data = /root/.n8n
    ]:
  ]:

]:
