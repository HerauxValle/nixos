# Seed Architecture & Design Decisions

## The SD Stack

| File | Docker Equiv | Description |
|------|-------------|-------------|
| `.sdc` | Dockerfile + Compose | Blueprint — text, lives anywhere |
| `.sdl` | Image | Layer — rootfs + deps, btrfs snapshot |
| `.sdx` | Container | Execution — btrfs snapshot of SDL |
| `.sdp` | Volume | Persistence — btrfs subvol, CoW |
| `.img` | - | Orchestrator — LUKS loopback btrfs |

All SD files are self-contained. Nothing references host paths. Everything resolves inside the container's isolated rootfs.

---

## File Format

All binary SD files (SDL, SDX, SDP) share the same container format:

```
[4 bytes]   magic: SD\x01\x02
[header]    JSON metadata (see below)
[data]      zstd-compressed btrfs send stream
[checksum]  sha256 of data block
```

### Header fields

```jsonc
{
  "type":         "sdl",           // sdl / sdx / sdp
  "version":      "1.0",
  "hash":         "sha256...",     // hash of SDC content + build timestamp
  "created":      "2026-01-01T00:00:00",
  "layer_hash":   "sha256...",     // SDL this was built from (SDX/SDP only)
  "source":       "ubuntu:22.04",  // known distro = no full rootfs embedded
  "nodatacow":    false,           // true for high-write SDPs
  "manifest":     {}               // type-specific metadata
}
```

Dependencies are referenced by hash only — never by path. Portability guaranteed.

---

## Layering

Two layers max per blueprint — keeps it simple:

```
base layer  = rootfs + [deps]
app layer   = base + [install] steps
SDX         = btrfs snapshot of app layer
```

Layer cache works by hashing blueprint sections independently:
- `[deps]` hash unchanged → reuse base layer
- `[install]` hash unchanged → reuse app layer
- Only rebuild what changed

---

## Storage Layout (inside .img)

```
myproject.img/
  meta.toml
  blueprints/       ← .sdc files
  layers/           ← SDL subvols (keyed by hash)
    abc123/         ← base layer
    def456/         ← app layer
  containers/       ← SDX subvols
    ollama-1/
      rootfs/
      meta.toml     ← status, layer_hash, sdp mounts, pid
  profiles/         ← SDP subvols
    models/
    logs/
  formats/          ← custom parser rulesets
  config/           ← img-specific config overrides
  help/             ← img-specific docs
  logs/
```

---

## Known Issues & Solutions

### 1. No layer caching → full rebuild on change
**Solution:** Content-addressed layers. Hash `[deps]` and `[install]` sections separately. Reuse unchanged layers. Max two layers per blueprint.

### 2. Storage bloat from orphaned snapshots
**Solution:** Reference counting in SDL `meta.toml`. Track how many SDXs reference each SDL. `sd prune` only deletes SDLs with zero references. Auto-decrements on `sd delete container`.

### 3. High-write SDP CoW slowdown (databases etc)
**Solution:** Set `nodatacow` (`chattr +C`) on SDP subvols automatically at creation. Declared in SDP header. Trades CoW efficiency for write performance.

### 4. Everything must be on same btrfs partition
**By design:** Everything lives inside the `.img` — one btrfs filesystem. External files use btrfs send streams. Re-import via `btrfs receive`. Not a limitation, just the architecture.

### 5. Metadata sync for running containers
**Solution:** SDX `meta.toml` stores `status`, `layer_hash`, `pid`. Stale check on every `sd` command — if PID no longer exists, mark as stopped and clean up.

### 6. Concurrent writes to same SDP
**Solution:** SDP mount modes enforced at mount time:
- `exclusive` (default) — one writer only
- `readonly` — many readers
Stored in SDP metadata. Error if exclusive SDP already mounted.

### 7. Rootfs distribution size
**Solution:** SDL header stores `source`. If source is a known distro (`ubuntu:22.04`, `alpine:3.19` etc), only the delta is stored in the SDL file — not the full rootfs. Full rootfs only embedded for unknown/custom sources.

### 8. Namespace and cgroup leak on crash
**Solution:** PID file + auto-cleanup. On any `sd` command, scan for SDX PIDs that no longer exist → clean up their cgroups and namespaces automatically before proceeding.

### 9. Layer hash collision
**Solution:** Hash SDC content + build timestamp, not the resulting filesystem. Guarantees uniqueness even for identical blueprints built at different times.

### 10. btrfs operations require root
**Note:** All btrfs/LUKS/namespace operations use `sudo`. Documented requirement. Future: investigate user namespaces to reduce sudo surface.

### 11. Closing img with running containers
**Solution:** `sd close` checks for running SDXs first. Errors with list of active containers. Use `sd close --force` to stop all containers then close.

---

## Update Flow

### SDC changes
```
new SDC hash detected
→ rebuild affected layers (only changed sections)
→ flag SDXs using old layer hash as "outdated"
→ sd update container <name>
  → stop SDX
  → new SDX snapshot on new layer
  → remount SDPs
  → start SDX
```

### SDP update
```
SDP is a mounted folder
→ changes visible to SDX immediately on next start
→ no rebuild needed
```

### SDX export/import
```
export: btrfs send → .sdx file (includes header + compressed stream)
import: btrfs receive into img → new SDX subvol
move between machines: copy .sdx file → import on target
```

---

## Isolation

Full namespace isolation by default. All can be disabled per-blueprint in `[isolation]`.

| Namespace | Default | What it isolates |
|-----------|---------|-----------------|
| network   | true    | network interfaces |
| pid       | true    | process tree |
| mount     | true    | filesystem mounts |
| uts       | true    | hostname |
| ipc       | true    | inter-process communication |
| user      | true    | user/group IDs |

Kernel namespace is always shared — unavoidable.

---

## Resource Limits (cgroups)

Declared in `[resources]` block of SDC:

```
[resources]:[
memory = 4gb
cpu    = 2
gpu    = 0
]:
```

GPU/VRAM limiting is outside cgroups scope — handled separately via device passthrough.

---

## Rootfs Sources

```
ubuntu          → ubuntu:latest
ubuntu:22.04    → specific version
alpine:3.19     → alpine linux
arch            → arch linux
debian:12       → debian bookworm
```

Pulled from `images.linuxcontainers.org` as rootfs tarballs. Cached as base SDL inside img.

---

## Prune Strategy

```
sd prune        → removes SDLs with 0 SDX references
                  removes stopped SDXs older than threshold
                  removes orphaned SDP mounts
sd prune --all  → removes everything not currently running
```

Reference counts updated automatically on container create/delete.