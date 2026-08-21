# Principles

> **Own the complexity you understand. Outsource the complexity you don't want to become an expert in.**

Become an expert where it matters to your goals. Delegate everything else to well-understood tools instead of reinventing them.

---

> **Declare the state. Materialize the impurity. Never manually maintain the impurity.**

Mutable state should always be generated from a declarative source of truth. If it drifts or breaks, regenerate it instead of repairing it by hand.

---

> **Interfaces are for humans. Implementations are for machines.**

Expose a simple, well-documented interface. Hide implementation details behind stable abstractions.

# Project Structure

## Files

### `default.nix`

Contains imports and `mkOption` declarations.

- Defines the module interface.
- Imports only files within its own directory.

### `lib/`

Shared implementation code.

- Home for reusable abstractions and helper functions.
- Keeps higher-level modules concise and focused.

### `docs/`

Project-specific documentation.

- Tracks implementation details.
- Explains design decisions and internal behavior.

### `glossar/`

Configuration reference.

- Contains real, 1:1 Nix examples.
- Documents the public `config.vars.*` interface.
- Intended for users configuring the system, not developing it.

### `config/`

User-editable configuration.

- Defines `config.vars.*`.
- Describes **what** the system should do.
- Contains no implementation logic.

### `modules/`

System implementation.

- Contains the declarative Nix code that realizes `config.vars.*`.
- Intended for developing and extending the system itself.
- Generally not touched when simply configuring the system.
