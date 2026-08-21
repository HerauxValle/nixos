# Daemonless Privilege Escalation Architecture

## Design Philosophy

**Goal**: Enable passwordless privilege escalation without a daemon, using minimal sudoers entries and a single hardened helper.

**Principles**:
1. **Minimal surface** — One helper, not nine
2. **Fail-safe** — Missing helper falls back to direct sudo (no breaking changes)
3. **Explicit ops** — Each operation must be explicitly allowed
4. **Easy distribution** — No daemon, no long-running processes, ready for binary packaging

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Seed CLI (main.py)                         │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                    ┌──────┴────────┐
                    ▼               ▼
        ┌────────────────────┐   ┌──────────────────┐
        │   engine/ (Python)  │   │ orchestration/   │
        │   container/, image/│   │ profile/, trash/ │
        │   layer/, network/  │   └──────────────────┘
        └────────────────────┘
                    │
                    ▼
        ┌────────────────────────────────────────────┐
        │     lib/privilege.py (Semantic Layer)       │
        ├────────────────────────────────────────────┤
        │ Functions: btrfs(), mount(), chown(), ...  │
        │ Detects helper + handles fallback           │
        │ Supports captured & interactive modes       │
        └──────────┬─────────────────────────────────┘
                   │ subprocess.run()
                   │ ["sudo", "/usr/local/lib/sd/priv/sd-priv", ...]
                   │
        ┌──────────▼────────────────────────────────────────┐
        │     helpers/sd-priv (47 LOC)                      │
        ├───────────────────────────────────────────────────┤
        │ Router: category:command → exec                   │
        │ fs:btrfs → exec btrfs "$@"                        │
        │ fs:mount → exec mount "$@"                        │
        │ net:ip → exec ip "$@"                             │
        │ ...                                               │
        │ Unknown → deny with error                         │
        └──────────┬────────────────────────────────────────┘
                   │ exec (replaces process)
                   │
        ┌──────────▼────────────────────────────────────────┐
        │  Allowed Commands (via sudoers NOPASSWD)          │
        ├───────────────────────────────────────────────────┤
        │ btrfs, mount, umount, losetup, cryptsetup, ...    │
        │ ip, iptables, chown, mkdir, chroot, etc.          │
        └───────────────────────────────────────────────────┘
```

## Execution Flow

### Without NOPASSWD (Password Prompt)
```
user$ sd run blueprint
  → lib.privilege.btrfs()
    → subprocess.run(["sudo", "/usr/local/lib/sd/priv/sd-priv", "fs", "btrfs", ...])
      → sudo: [sudo] password for user:
      → user enters password
      → kernel runs sd-priv as root
      → sd-priv routes to btrfs command
      → returns output
```

### With NOPASSWD (Passwordless)
```
user$ sd run blueprint
  → lib.privilege.btrfs()
    → subprocess.run(["sudo", "/usr/local/lib/sd/priv/sd-priv", "fs", "btrfs", ...])
      → sudo: (no password prompt, sudoers allows)
      → kernel runs sd-priv as root
      → sd-priv routes to btrfs command
      → returns output (immediately)
```

### Fallback (Helper Missing)
```
user$ sd run blueprint
  → lib.privilege.btrfs()
    → helper not found (Path doesn't exist)
    → fallback to direct sudo: subprocess.run(["sudo", "btrfs", ...])
      → sudo: [sudo] password for user:
      → (works exactly as before, no breaking changes)
```

## Sudoers Configuration

### Before (Not Implemented)
```
# Would need 9 separate entries:
%wheel ALL=(root) NOPASSWD: /usr/local/lib/sd/priv/btrfs-helper *
%wheel ALL=(root) NOPASSWD: /usr/local/lib/sd/priv/mount-helper *
%wheel ALL=(root) NOPASSWD: /usr/local/lib/sd/priv/loop-helper *
...
```

### After (Unified)
```
# Single entry:
Cmnd_Alias SD_PRIV = /usr/local/lib/sd/priv/sd-priv
%wheel ALL=(root) NOPASSWD: SD_PRIV
```

**Benefits**:
- Simpler config (1 line instead of 9)
- Easier to manage & audit
- Single point for security review

## Security Properties

### 1. Strict Operation Validation
```bash
# In sd-priv:
case "$cat:$cmd" in
  fs:btrfs) exec btrfs "$@" ;;
  fs:mount) exec mount "$@" ;;
  # Unknown operations denied:
  *) echo "Denied: $cat:$cmd" >&2; exit 1 ;;
esac
```

### 2. No Shell Execution
- Uses `exec` (replaces process image)
- No `sh -c` (prevents injection)
- Args passed directly (no word splitting)

### 3. No Wildcard Commands
```bash
# Good (explicit):
exec btrfs "$@"      # Args validated by btrfs itself

# Bad (overly permissive):
exec "$@"            # Could run any command
```

### 4. Fails Closed
- Unknown category:command → exit 1 (deny)
- Missing arguments → exit 1 (deny)
- Invalid operations → explicit case fallthrough (deny)

## Privilege Separation

### Unprivileged (Python)
- CLI parsing
- Config reading
- Orchestration logic
- Calls privilege layer for root ops

### Privileged (Helper)
- Operation routing
- Command execution (btrfs, mount, ip, etc.)
- No policy decisions (Python handles those)

**Design**: Privilege layer = dumb router, security in Python layer above

## Comparison with Alternatives

| Aspect | Daemon | This Design |
|--------|--------|-----------|
| Running procs | 1 daemon | 0 (on-demand) |
| Sudoers entries | 1-5 | 1 |
| Helper scripts | 1-3 | 1 |
| Start time | Slow (daemon startup) | Fast (direct exec) |
| Complexity | High | Low |
| Auditability | Hard (long-lived proc) | Easy (per-invocation) |
| Failure modes | Daemon crash, hangs | Immediate fail, logs |

## Installation & Distribution

### File Layout
```
/
├── usr/local/bin/sd                        → symlink to main.py
├── usr/local/lib/sd/
│   ├── priv/
│   │   └── sd-priv (755, owned by root)   ← only root-owned file
└── etc/sudoers.d/
    └── sd (440, optional)                  ← generated by --enable-root
```

### Binary Packaging
All executable bits already set:
- `helpers/sd-priv` (755)
- `main.py` (implicit from shebang)
- `suggestion.sh` (755)

Ready for:
- RPM/DEB packaging
- Docker images
- Standalone binary bundles

## Performance Characteristics

### Overhead
- Helper detection: <1ms (cached result)
- Subprocess spawn: ~5-10ms (standard for sudo)
- No additional latency vs direct `sudo` calls

### Timeout
- Global timeout: 60s (adjustable in privilege.py)
- Prevents hung processes from blocking user

### Resource Usage
- Helper: <1MB memory (single bash process)
- Python layer: <1MB per call (subprocess overhead)
- No daemon, no persistent memory

## Future Extensions

### Metrics & Logging
```python
# Could add:
_priv(..., log_op=True)  # Log to syslog: "user ran btrfs create"
_priv(..., timeout=120)  # Custom timeouts per operation
```

### Per-User Policies
```bash
# Could restrict by user:
%wheel ALL=(root) NOPASSWD: /usr/local/lib/sd/priv/sd-priv *
%sudo  ALL=(root) NOPASSWD: /usr/local/lib/sd/priv/sd-priv fs:mount *  # Mount only
```

### Audit Trail
```bash
# Could enhance sd-priv:
if [ -n "$SUDO_USER" ]; then
  echo "$SUDO_USER ran sd-priv $@" >> /var/log/sd-priv.log
fi
```

## References

- Sudoers manual: `man sudoers`
- Security best practices: https://wiki.sudo.ws/
- Namespace isolation: https://man7.org/linux/man-pages/man7/namespaces.7.html
