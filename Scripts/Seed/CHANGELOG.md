# Changelog

## v1.4.1 — Complete Sandboxing System (AppArmor, Landlock, Seccomp, Introspection)

**Release Date:** 2026-04-01

### Core Features

#### AppArmor Backend (Foundation)
- **SecuritySpec IR**: Normalized internal representation for security constraints
- **Profile Generator**: String-template based, deterministic, zero external dependencies
- **AppArmorManager**: Load profiles via `apparmor_parser`, generate aa-exec commands
- **Three Isolation Presets**: `strict` (no /tmp, /var, network), `default` (balanced), `permissive` (debug)
- **Binary Resolver**: Symlink resolution, shebang detection, interpreter path auto-detection
- **Blueprint Integration**: Parse `[run]:[security]:[profile = ...]` block

#### Landlock Backend (Unprivileged Alternative)
- **Kernel Detection**: Graceful check via `/proc/sys/kernel/landlock.syscall`
- **Rule Generation**: Map SecuritySpec → Landlock hierarchical allow-list (read-only, writable, executables)
- **LandlockEnforcer**: Kernel-enforced restrictions without root (Linux 5.13+)
- **Backend Selection**: AppArmor > Landlock > none (auto-select best available)

#### Seccomp + AppArmor Synergy (Defense in Depth)
- **Dynamic Syscall Restrictions**: Map SecuritySpec isolation to syscall blocks
- **Network Isolation**: If `network_enabled=False`, block socket/bind/connect/listen family
- **Layered Enforcement**: Syscall layer (coarse) + Filesystem layer (fine-grained)
- **No Duplication**: Seccomp handles syscalls, AppArmor handles paths

#### Profile Introspection & Debugging
- **Profile Metadata**: Every profile includes name, timestamp, SecuritySpec dump, debug guide
- **Deterministic Caching**: SHA256 hashing of SecuritySpec (first 8 chars) for cache reuse
- **Profile Storage**: Store at `/var/lib/seed/apparmor/{service}.profile.{hash}` with JSON metadata
- **Violation Detection**: Parse `/var/log/audit/audit.log` for AppArmor denials
- **Remediation Suggestions**: Auto-generate fix hints for failed operations

### Implementation

**New Modules:**
- `lib/sandboxing/backends.py` — Backend registry + selection
- `lib/sandboxing/landlock/compat.py` — Kernel version detection
- `lib/sandboxing/landlock/rules.py` — SecuritySpec → Landlock rules
- `lib/sandboxing/landlock/enforcer.py` — Unprivileged enforcement
- `lib/apparmor/introspection.py` — Metadata, caching, violation detection

**Modified Files:**
- `lib/seccomp/profile.py`: Added `get_restricted_syscalls(spec)` for spec-aware syscall filtering
- `lib/apparmor/generator.py`: Enhanced with metadata section generation
- `lib/apparmor/manager.py`: Profile storage on disk for debugging
- `parser/processing/types.py`: Added `security_preset` to RunConfig
- `parser/processing/run.py`: Parse `[run]:[security]:` block
- `engine/container/run.py`: Single integration point for all backends
- `install.sh`: AppArmor availability detection

**Architecture:**
```
SecuritySpec (single source of truth)
  ↓
Backend Selection: AppArmor > Landlock > none
  ↓
Defense Layers (independent):
  1. Seccomp — block dangerous syscalls
  2. AppArmor/Landlock — restrict filesystem paths
  3. Capabilities — (future)
  4. Resource limits — (existing cgroups)
```

### Security Patterns Applied
- Input validation: `safe_name()`, `safe_path_within()`
- Privilege guards: Availability checks before tool use
- Timeout protection: 30s limit on external tools
- Structured error handling: `error()` + `emit()` with codes
- No pass-through commands: Semantic APIs only
- Graceful fallback: No errors when features unavailable

### Testing
- 8 comprehensive tests (all pass on Linux 6.18)
  - Kernel detection, rule generation, syscall restrictions, hashing, metadata, backend selection
- All modules compile, zero external dependencies
- Integration verified with container execution pipeline

### Runtime Dependencies Baseline
- DNS: `/etc/resolv.conf`, `/run/systemd/resolve/stub-resolv.conf`
- User/group: `/etc/passwd`, `/etc/group`, `/etc/nsswitch.conf`
- Interpreters: `/usr/lib/python*`, `/usr/lib/ruby*`, `/usr/lib/node*`, `/usr/lib/perl*`
- Localization: `/usr/share/locale`, `/usr/share/zoneinfo`
- TLS: `/etc/ssl`, `/usr/share/ca-certificates`

### What This Means

- **For users without AppArmor**: Landlock provides unconfined → confined transition
- **Stronger isolation**: Multiple layers (seccomp + filesystem) can't all be bypassed
- **Better debugging**: Profiles include debug guide, violations auto-detected, remediation suggested
- **Cache efficiency**: Identical specs reuse cached profiles by deterministic hash
- **Backwards compatible**: No changes to existing security layer, all features optional

### Key Design Decisions

1. **SecuritySpec is the Source** — All backends derive from single spec, no duplication
2. **Graceful Degradation** — Best available enforcement, no errors on unsupported systems
3. **No Hardcoded Exceptions** — Generator is source of truth, improve rules don't add special cases
4. **Defense in Depth** — Each layer independent, multiple layers = stronger isolation
5. **Zero External Dependencies** — Python stdlib only, no Jinja2, pip packages, or new tools


