# SDC Blueprint Format

Seed blueprints are `.sdc` files that define containerized services. They use a simple block-based syntax.

## Basic Structure

```sdc
[main]:[
  [meta]:[
    sdc_version = 1
    name        = servicename
    author      = yourname
  ]:
  [services]:[
    servicename
  ]:
  [startup]:[
    servicename
  ]:
]:

[servicename]:[
  [env]:[ ... ]:
  [build]:[ ... ]:
  [run]:[ ... ]:
]:
```

## Blocks

### `[meta]:`
- `sdc_version` — Always `1`
- `name` — Service name (alphanumeric + underscore)
- `author` — Your name

### `[services]:`
List of service names to define in this blueprint (newline-separated).

### `[startup]:`
Which services to auto-start when container runs (newline-separated).

### `[env]:`
Environment variables. Format: `KEY = value`
- Values with spaces must be quoted
- `KEY =` (empty) is allowed
- Used in build and runtime

### `[build]:`
Container build instructions.

#### `[general]:`
- `rootfs` — Base image: `ubuntu:22.04`, `alpine:latest`, URL, or local tarball path
- `[deps]:` — Dependencies to install (multiple managers supported)
  - `pkg: package1 package2` — System packages via package manager
  - `pip: package1 package2` — Python packages
  - `cargo: crate1 crate2` — Rust crates
  - Other managers auto-discovered from `core/builder/managers/`

#### `[install]:`
Shell commands to run during build (one per line). Newlines preserved.

### `[run]:`
Runtime configuration.

#### `[config]:`
- `entrypoint` — Command to execute when container starts
- `port` — Port mapping: `HOST:CONTAINER` (e.g., `8188:8188` or `3000:3000`)
  - Can be a list for multiple ports
- `restart` — Restart policy: `on-failure`, `always`, or leave blank for no restart

#### `[storage]:`
Volume mounts. Format: `label = /container/path`
- Stored on host, mounted into container
- Example: `models = /opt/comfyui/models`

## Syntax Rules

- All blocks use `[name]:[ ... ]:` syntax
- Keys are left-aligned (no indentation needed, but can be)
- Values can span multiple lines in `[install]:` and `[storage]:`
- Comments: Lines starting with `#` are ignored
- Empty values allowed: `KEY =`
- Quoted strings: `"value with spaces"`

## Example

```sdc
[main]:[
  [meta]:[
    sdc_version = 1
    name        = myapp
    author      = me
  ]:
  [services]:[
    myapp
  ]:
  [startup]:[
    myapp
  ]:
]:

[myapp]:[
  [env]:[
    APP_HOST = 0.0.0.0
    APP_PORT = 5000
    DEBUG = false
  ]:

  [build]:[
    [general]:[
      rootfs = ubuntu:22.04
      [deps]:[
        pkg: python3 python3-pip git
        pip: flask requests
      ]:
    ]:
    [install]:[
      git clone https://github.com/user/repo /app
      cd /app
      pip install -r requirements.txt
    ]:
  ]:

  [run]:[
    [config]:[
      entrypoint = python /app/main.py
      port       = 5000:5000
      restart    = on-failure
    ]:
    [storage]:[
      data = /app/data
      logs = /app/logs
    ]:
  ]:
]:
```

## Tips

- Keep `[install]:` commands short — one logical step per line
- Use `rootfs` URLs for reproducibility
- `pkg:` uses the detected package manager (apt, apk, etc.)
- Storage mounts are created on first run
- Env vars in `[build]:[install]:` are automatically exported
