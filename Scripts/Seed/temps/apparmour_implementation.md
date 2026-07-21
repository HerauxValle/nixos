Here’s a clean, **handoff-ready Markdown plan** you can give to other models/tools. No code, just architecture and implementation direction.

---

```markdown
# AppArmor Integration Plan (Seed Runtime)

## Goal

Integrate AppArmor as a **first-class, modular security backend** that is:

- Automatically generated from SDC blueprints
- Fully isolated from runtime logic
- Composable with existing security layers (seccomp, capabilities)
- Maintainable and extensible

---

## High-Level Architecture

AppArmor should be implemented as part of a **dedicated security layer**, not embedded in runtime logic.

### Core Principle

Treat AppArmor as a **pluggable sandbox backend**, similar to:

- seccomp (syscall filtering)
- capabilities (privilege reduction)

---

## Folder Structure

Recommended structure:

```

security/
apparmor/
manager/        # runtime interaction (load, apply, detect)
generator/      # profile generation logic
templates/      # base profiles and presets
resolver/       # blueprint → security model

```

Alternative (less ideal but acceptable):

```

privilege/apparmor/

```

---

## Data Flow

AppArmor should follow a **multi-stage transformation pipeline**:

```

SDC Blueprint
↓
Parsed AST
↓
Internal IR
↓
Security Specification (SecuritySpec)
↓
AppArmor Profile Generation
↓
Profile Load + Apply at Runtime

```

---

## Security Specification Layer

Introduce a normalized internal structure (e.g. `SecuritySpec`) derived from the blueprint.

### Responsibilities

- Abstract runtime requirements into security rules
- Decouple blueprint parsing from profile generation
- Serve as the single source of truth for all sandboxing layers

### Derived Information

From the blueprint, extract:

- Filesystem access (mounts, writable paths)
- Executable paths (entrypoint, required binaries)
- Network usage (ports, enabled/disabled)
- Runtime behavior (process model, isolation level)
- Optional: capabilities, privilege requirements

---

## Blueprint → Security Mapping

Map existing SDC fields into security constraints:

### Storage

- Defines writable filesystem paths
- Everything else should default to restricted or read-only

### Entrypoint

- Defines allowed executables
- May require resolving interpreters (e.g. Python)

### Dependencies

- Imply additional binaries that must be executable
- Should be resolved via existing package manager logic

### Ports

- Enable or disable network access
- Define network scope

### Install Phase

- Must be ignored for runtime profiles
- Only runtime behavior is relevant

---

## Profile Generation Strategy

Use a **template-based system with dynamic rule injection**.

### Template Design

- Base template defines:
  - Default deny posture
  - Minimal system access
- Dynamic sections:
  - Filesystem rules
  - Execution rules
  - Network rules

### Rule Categories

1. Filesystem
   - Writable paths from storage
   - Read-only system paths
   - Temporary directories

2. Execution
   - Explicitly allowed binaries
   - Interpreter handling

3. Network
   - Disabled by default unless required
   - Basic socket permissions when enabled

---

## Isolation Presets

Support predefined security levels:

- `strict`
  - Deny everything except explicitly declared resources
- `default`
  - Allow common runtime behavior
- `permissive`
  - Relaxed restrictions for compatibility

Blueprints may optionally define:

```

[run]: [security]:

profile = strict

```

---

## Runtime Integration

AppArmor should be applied at a **single, well-defined point** in the execution pipeline.

### Integration Point

- Immediately before process execution
- Same stage as:
  - seccomp filter application
  - capability dropping

### Responsibilities

- Ensure AppArmor is available on host
- Load profile if not already loaded
- Attach profile to process

---

## CLI Integration (Optional but Recommended)

Expose AppArmor management via CLI:

- List profiles
- Load/unload profiles
- Inspect generated profiles

---

## Design Constraints

### Must Do

- Keep AppArmor logic fully isolated from runtime code
- Generate profiles dynamically from blueprint-derived data
- Use templates instead of hardcoded rules
- Ensure deterministic and reproducible profile generation

### Must Not Do

- Do not scatter AppArmor logic across the codebase
- Do not hardcode profiles inside Python logic
- Do not mix build-time and runtime behavior
- Do not tightly couple to specific services

---

## Known Challenges

- Interpreted languages (e.g. Python) require broader read access
- Temporary directories must be explicitly allowed
- DNS and system files may be required for networking
- Over-restrictive profiles will break applications

---

## Iteration Strategy

Start minimal and expand:

### Phase 1 (MVP)

- Filesystem rules (storage-based)
- Execution rules (entrypoint-based)
- Basic network toggle
- Single base template

### Phase 2

- Dependency-aware execution rules
- Multiple templates / presets
- Improved filesystem modeling

### Phase 3

- Fine-grained network control
- Capability-aware restrictions
- Auto-generated least-privilege profiles

---

## Long-Term Vision

Enable fully automated sandboxing:

> Blueprint → Deterministic, reproducible, least-privilege runtime environment

This positions the system as a **declarative container + security engine**, not just a runtime.

---
```
