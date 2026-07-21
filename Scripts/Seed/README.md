# Seed (`sd`)

Lightweight container runtime using Btrfs snapshots + Linux namespaces. No daemon, no orchestration overhead — just fast, isolated containers.

## Features

- No daemon (direct Btrfs snapshotting)
- Instant containers (copy-on-write layers)
- Full namespace isolation (PID, mount, net, etc.)
- Auto cleanup with layer reference counting
- Blueprint-based reproducible containers (`.sdc`)
- Pattern matching (`*`, `-all`) across commands
- LUKS encryption (Argon2, named slots)
- Profiles + defaults
- Networking (veth, DNS, port forwarding)

## Install

```bash
./install.sh
````

## Basic Usage

```bash
sd run myblueprint -name mycontainer
sd stop mycontainer
sd restart mycontainer
sd exec mycontainer bash
sd logs mycontainer -f
sd delete container mycontainer
sd prune
```

## Patterns

```bash
sd stop ollama*
sd restart *test*
sd logs openwebui*
sd stop -all
sd exec -all bash
```

## Core Commands

```
run, stop, restart, exec, logs, prune
create, edit, delete, list, validate
set, unset, rename, default, reset
db, which, encryption, help
```

## Architecture

* Single Btrfs root (`/mnt/sd`)
* Snapshot-based containers + layers
* Reference-counted cleanup
* veth networking + optional DNS/proxy
* LUKS encryption (Argon2)

Override root:

```bash
SD_ROOT=/custom/path sd list containers
```

## License

Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0).

Additional terms apply — see `TERMS.md`.

* Free to use, modify, and share
* Must open-source changes (including SaaS)
* Attribution required
* No warranty

If any additional term is unenforceable, AGPL-3.0 applies fully.

---

**Seed** — fast, minimal, Btrfs-powered containers.