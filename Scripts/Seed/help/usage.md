# Seed (`sd`)

A lightweight, filesystem-based container management system using Btrfs snapshots and Linux namespaces. No daemon, no complex orchestration—just fast container creation, execution, and cleanup.

## Features

- **Zero-Daemon Architecture**: Direct Btrfs snapshot management, no persistent service
- **Instant Containers**: Snapshot-based layers with copy-on-write isolation
- **Namespace Isolation**: Full process, network, mount, and PID namespacing
- **Smart Cleanup**: Automatic layer reference counting and cascade deletion
- **Flexible Storage**: Configurable rootfs images with layered snapshots
- **Pattern Matching**: Wildcard support (`*xxx`, `xxx*`, `*xxx*`) and `-all` flags across commands
- **Blueprints**: Declarative `.sdc` format for reproducible container setup
- **Encryption**: LUKS-based encryption with Argon2 key derivation and named slots
- **Profiles**: Named container profiles with default selection
- **Port Forwarding & Networking**: veth pairs, DNS, and proxy support

## Installation

```bash
./install.sh
```

This creates a symlink at `/usr/local/bin/sd` to the main CLI.

## Uninstallation

```bash
./install.sh uninstall
```

## Basic Usage

### Run a container from a blueprint

```bash
sd run myblueprint
sd run myblueprint -name mycontainer
```

### Container management

```bash
# Start / stop / restart
sd stop mycontainer
sd restart mycontainer

# Execute a command
sd exec mycontainer bash

# Logs
sd logs mycontainer
sd logs mycontainer -f
sd logs mycontainer -lines 100

# Delete
sd delete container mycontainer
sd prune
```

### Pattern matching and `-all`

```bash
sd stop ollama*          # Stop all containers starting with "ollama"
sd restart *test*        # Restart all containers containing "test"
sd logs openwebui*       # Show logs for matching containers
sd stop -all             # Stop all running containers
sd delete container -all # Delete all stopped containers
sd exec -all bash        # Run command in all containers
```

## Commands

### `run`

```
sd run <blueprint> [-name/-n <name>] [-all]
```

Run a container from a blueprint.

---

### `stop`

```
sd stop [<name>] [-all]
```

Stop running container(s). Supports pattern matching.

---

### `restart`

```
sd restart [<name>] [-all]
```

Restart container(s). Supports pattern matching.

---

### `exec`

```
sd exec [<name>] <cmd...> [-all]
```

Execute a command inside a container.

---

### `logs`

```
sd logs [<name>] [-f] [-lines <N>] [-all]
```

Show container logs. `-f` follows live output. `-lines` defaults to `50`.

---

### `prune`

```
sd prune [-all]
```

Remove stopped containers and unused layers.

---

### `select`

```
sd select <path> [-name/-n <name>] [-d <depth>]
```

Select a rootfs or image path. Depth defaults to `3`.

---

### `close`

```
sd close [<name>] [-all]
```

Close active container session(s). `sd close all` or `-all` closes everything; omitting `<name>` closes the active session.

---

### `create`

```
sd create image [-name/-n <name>] [-size/-s <size>]
sd create blueprint <path> [-ext <ext>]
sd create format <path>
sd create profile -container <container> <name>
```

Create images, blueprints, formats, or profiles.

---

### `edit`

```
sd edit blueprint [<name>] [-e <editor>] [-all]
sd edit format [<name>] [-e <editor>] [-all]
```

Open a blueprint or format in an editor.

---

### `delete`

```
sd delete image <path>
sd delete blueprint <path>
sd delete format <path>
sd delete container [<path>] [-all] [-container <name>]
sd delete profile -container <container> <name>
```

Delete images, blueprints, formats, containers, or profiles.

---

### `list`

```
sd list blueprints
sd list formats
sd list images
sd list containers
sd list layers
sd list profiles
sd list processes
sd list db
sd list config
sd list rules
```

List resources of the specified type.

---

### `validate`

```
sd validate blueprint [<name>] [-all]
sd validate preset [<name>] [-all]
```

Validate a blueprint or preset.

---

### `set` / `unset`

```
sd set <rule> <key> <value>
sd unset <rule> <key>
```

Set or unset a rule key-value pair.

---

### `rename`

```
sd rename profile -container <container> <old> <new>
```

Rename a profile.

---

### `default`

```
sd default profile [<profile>] -container <container>
```

Set the default profile for a container.

---

### `reset`

```
sd reset config
```

Reset configuration to defaults.

---

### `db`

```
sd db <name>
```

Show the database entry for a container.

---

### `which`

```
sd which image
```

Show which rootfs image is currently active.

---

### `encryption`

```
sd encryption add    [<arg1>] [-name/-n <name>] [-preset <preset>]
sd encryption create [<arg1>] [-name/-n <name>] [-preset <preset>]
                     [-argon2-memory <n>] [-argon2-time <n>] [-argon2-parallel <n>]
sd encryption delete [<arg1>]
sd encryption list
sd encryption verify [-n/-name <name>]
sd encryption unverify <arg1>
sd encryption rename <old> <new>
sd encryption refresh [<arg1>] [-preset <preset>]
sd encryption enable
sd encryption disable
```

Manage LUKS encryption slots with Argon2 key derivation.

---

### `help`

```
sd help
```

Show help.

---

## Architecture

### Storage

All container data lives in a **single Btrfs filesystem** configured at runtime:

```
/mnt/sd/
├── images/          # Rootfs images (usually mounted read-only)
├── containers/      # Live container snapshots
├── layers/          # Layer snapshots for container instances
└── metadata/        # Container state files
```

Override the default path with the `SD_ROOT` environment variable:

```bash
SD_ROOT=/custom/path sd list containers
```

### Container Lifecycle

1. **Run** — Resolve blueprint → snapshot rootfs → create container layer
2. **Start** — Launch unshare namespaces → run init in layer
3. **Exec** — Join container namespace → execute command
4. **Stop** — Terminate init process
5. **Delete** — Remove snapshot → decrement layer refs → cascade cleanup

### Reference Counting

Each layer tracks how many containers depend on it. When a container is deleted:
- Layer ref count decrements
- If count reaches 0, layer is auto-deleted
- Orphaned parent layers clean up recursively

### Networking

Containers use veth pairs with optional DNS, port forwarding, and proxy support.

### Encryption

LUKS-backed encryption with named slots. Keys are derived via Argon2 with configurable memory, time, and parallelism parameters. Presets available via `encryption-presets.jsonc`.

## Project Structure

```
.
├── main.py                  # CLI entry point
├── install.sh               # Install/uninstall script
├── README.md
├── CHANGELOG.md
├── blueprints/
│   ├── README.md            # .sdc format documentation
│   ├── ollama.sdc
│   ├── comfyui.sdc
│   ├── openwebui.sdc
│   └── n8n.sdc
├── cli/
│   ├── commands.py          # Command schema and dispatch tables
│   ├── handlers.py          # Command execution logic
│   ├── parser.py            # Argument parsing
│   ├── all_handler.py       # -all flag logic
│   ├── completion.py        # Shell completion
│   └── help.py              # Help rendering
├── core/
│   ├── container/
│   │   ├── run.py
│   │   ├── stop.py
│   │   ├── restart.py
│   │   ├── exec.py
│   │   ├── logs.py
│   │   ├── delete.py
│   │   ├── list.py
│   │   └── health.py
│   ├── image/
│   │   ├── create.py
│   │   ├── delete.py
│   │   ├── list.py
│   │   └── select.py
│   ├── network/
│   │   ├── manager.py
│   │   ├── veth.py
│   │   ├── dns.py
│   │   ├── forward.py
│   │   └── proxy.py
│   ├── encryption/
│   │   ├── slots.py
│   │   ├── luks.py
│   │   ├── derive.py
│   │   ├── presets.py
│   │   ├── guard.py
│   │   └── keyfile.py
│   ├── profile/
│   │   ├── create.py
│   │   ├── delete.py
│   │   ├── rename.py
│   │   ├── set_default.py
│   │   └── list.py
│   ├── blueprint/
│   │   ├── blueprint.py
│   │   ├── validate.py
│   │   ├── build.py
│   │   └── run.py
│   └── session.py
└── tests/
    ├── cmd.py
    ├── script.sh
    ├── test_ir.py
    ├── test_renderers.py
    ├── test_port_forward.py
    └── verify_commands.py
```

## Configuration

Default storage root is `/mnt/sd`. Override:

```bash
SD_ROOT=/custom/path sd list containers
```

Config can be reset with:

```bash
sd reset config
```

## Development

Debug/test commands (available when `tests/script.sh` is present):

```bash
sd penetrate
sd penetrate <suite>
```

## Troubleshooting

**Container exits immediately after start:**
- Check logs: `sd logs <name>`
- Ensure rootfs image is valid and has `/proc` mounting in init

**Permission denied:**
- Most operations require `sudo` or membership in the `btrfs` group
- Check Btrfs filesystem permissions

**Symlink already exists:**
- Run `./install.sh` again to update
- Or manually: `sudo rm /usr/local/bin/sd && ./install.sh`

**Seed** — Lightweight containers, Btrfs-powered.