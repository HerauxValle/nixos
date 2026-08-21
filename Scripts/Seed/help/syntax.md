# Seed Blueprint Syntax (.sdc)

## Overview

Blueprints define how to build and run services. One `.sdc` file can define
multiple services. The parser reads top to bottom — order matters for execution.

Indentation is visual only and ignored by the parser.

---

## Block syntax

Open a block:  `[name]:[`
Close a block: `]:`
Chain close:   `]:]:` closes two blocks at once

Key-value:     `key = value`
Comment:       `# this is ignored`
Multiline comment: `""" ... """`

---

## File structure

```
[main]:[
  [meta]:[...]
  [services]:[...]
  [startup]:[...]
]:

[service_name]:[
  [meta]:[...]
  [env]:[...]
  [build]:[...]
  [run]:[...]
]:
```

---

## [main]

Top-level file config. Required.

### [meta]
```
[meta]:[
  sdc_version = 1        # required — parser rejects incompatible versions
  name        = my stack
  author      = you
  description = optional
]:
```

### [services]
```
[services]:[
  ollama
  db
]:
```
Raw lines — one service name per line. Order = declaration order.

### [startup]
```
[startup]:[
  db
  wait         = healthy   # wait for db health check to pass
  wait_timeout = 60s       # timeout per wait (default 60s)
  ollama
  wait         = 10s       # fixed delay
]:
```
Top to bottom execution. `wait = healthy` requires the previous service
to have a `[health]` block or parser warns at validate time.

---

## [service_name]

One block per service declared in `[services]`.

### [meta]
```
[meta]:[
  name    = ollama    # human label
  version = 0.18.2   # informational only
]:
```

### [env]
Available in both `[install]` scripts and at container runtime.
```
[env]:[
  OLLAMA_HOST    = 0.0.0.0
  OLLAMA_MODELS  = /models
  OLLAMA_VERSION = 0.18.2
]:
```
Use `$VAR` in entrypoint, install scripts, health cmd. Resolves at runtime.

---

## [build]

Defines how to build the SDL (layer). Built once, cached by content hash.
Deps change → base layer rebuilds. Install change → app layer rebuilds only.

### [general]
```
[general]:[
  rootfs = ubuntu:22.04   # distro:version or distro (uses latest)
  [deps]:[
    curl
    ca-certificates
    zstd
  ]:
]:
```
`rootfs` — pulled from `config/distros.jsonc`. Space or newline separated deps.
Package manager auto-detected from rootfs (apt/pacman/apk/dnf).

### [install]
Raw shell script. Runs inside chroot during app layer build.
Env vars from `[env]` are available.
```
[install]:[
  curl -fsSL https://ollama.com/install.sh | sh
  echo "installed $OLLAMA_VERSION"
]:
```

---

## [run]

Defines how to run the SDX (container).

### [config]
```
[config]:[
  entrypoint  = /usr/local/bin/ollama serve
  port        = 11434:11434   # container:host
  restart     = on-failure    # no / on-failure / always
  restart_max = 3             # max retries (conflicts with always = error)
  user        = 1000:1000     # uid:gid inside container
  workdir     = /             # working directory
  depends     = db            # start after this service
]:
```
`port` — only used when `network = true` in `[isolation]`.
When `network = false` (shared host network), port mapping ignored.
Multiple ports: use one line per port or comma separated.

### [resources]
```
[resources]:[
  memory = 8gb    # empty = no limit
  cpu    = 4      # empty = no limit
  gpu    = 1      # reserved, not yet implemented
]:
```
Backed by cgroups v2. Empty value = no limit applied.

### [isolation]
```
[isolation]:[
  network = true   # true = isolated namespace, false = share host
  pid     = true
  mount   = true
  uts     = true
  ipc     = true
]:
```
All default to `true` (full isolation) if block omitted.
Kernel namespace always shared — unavoidable.

### [health]
```
# port-based (default for network services)
[health]:[
  port     = 11434
  interval = 5s
  timeout  = 30s
  retries  = 3
]:

# cmd-based (for non-port services)
[health]:[
  cmd      = pg_isready -U $POSTGRES_USER
  interval = 5s
  timeout  = 10s
  retries  = 3
]:
```
Required if another service uses `wait = healthy` referencing this one.

### [storage]
```
[storage]:[
  models = /models              # SDP name = container mount path
  logs   = /var/log/ollama
]:
```
Each entry creates a persistent profile at `profiles/service/name/`.
No storage = fully ephemeral container (data lost on stop).
SDPs survive container stop/delete. Mountable by multiple containers (readonly).

Nested storage:
```
[storage]:[
  models:[
    checkpoints = /models/checkpoints
    cache       = /models/cache
  ]:
  logs = /var/log/ollama
]:
```

---

## Full example

```
[main]:[
  [meta]:[
    sdc_version = 1
    name        = ollama stack
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

  [meta]:[
    name    = ollama
    version = 0.18.2
  ]:

  [env]:[
    OLLAMA_HOST    = 0.0.0.0
    OLLAMA_MODELS  = /models
    OLLAMA_VERSION = 0.18.2
  ]:

  [build]:[
    [general]:[
      rootfs = ubuntu:22.04
      [deps]:[
        curl
        ca-certificates
        zstd
      ]:
    ]:
    [install]:[
      curl -fsSL https://ollama.com/install.sh | sh
    ]:
  ]:

  [run]:[
    [config]:[
      entrypoint  = /usr/local/bin/ollama serve
      port        = 11434:11434
      restart     = on-failure
      restart_max = 3
      user        = 1000:1000
      workdir     = /
    ]:
    [resources]:[
      memory = 8gb
      cpu    = 4
    ]:
    [isolation]:[
      network = true
      pid     = true
      mount   = true
      uts     = true
      ipc     = true
    ]:
    [health]:[
      port     = 11434
      interval = 5s
      timeout  = 30s
      retries  = 3
    ]:
    [storage]:[
      models = /models
      logs   = /var/log/ollama
    ]:
  ]:

]:
```

---

## Validation rules

- `sdc_version` mismatch → hard error
- Service in `[startup]` not in `[services]` → error
- `wait = healthy` with no `[health]` on target → warning
- `restart = always` + `restart_max` → error
- Duplicate service names → error
- Missing `rootfs` in `[general]` → error (no default rootfs)
- `depends` references unknown service → error

---

## Shebang

First line can declare a custom format ruleset:
```
#!myformat
```
Omit for default `.sdc` format.