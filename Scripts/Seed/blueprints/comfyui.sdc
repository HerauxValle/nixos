[main]:[
  [meta]:[
    sdc_version = 1
    name        = comfyui
    author      = herauxvalle
  ]:
  [services]:[
    comfyui
  ]:
  [startup]:[
    comfyui
  ]:
]:

[comfyui]:[

  [env]:[
    COMFYUI_HOST = 0.0.0.0
    COMFYUI_PORT = 8188
  ]:

  [build]:[
    [general]:[
      rootfs = ubuntu:22.04
      [deps]:[
        pkg: python3 python3-pip python3-venv git libgl1 libglib2.0-0
      ]:
    ]:
    [install]:[
      git clone --branch master https://github.com/comfyanonymous/ComfyUI /opt/comfyui
      python3 -m venv /opt/comfyui/venv
      /opt/comfyui/venv/bin/pip install --upgrade pip
      /opt/comfyui/venv/bin/pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
      /opt/comfyui/venv/bin/pip install -r /opt/comfyui/requirements.txt
    ]:
  ]:

  [run]:[
    [config]:[
      entrypoint = /opt/comfyui/venv/bin/python /opt/comfyui/main.py --listen 0.0.0.0 --port 8188 --cpu
      port       = 8188:8188
      restart    = on-failure
    ]:
    [storage]:[
      models   = /opt/comfyui/models
      outputs  = /opt/comfyui/output
      inputs   = /opt/comfyui/input
    ]:
  ]:

]:
