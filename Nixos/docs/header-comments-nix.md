# Nix Comment Header Style Guide

## Goal

Every `.nix` file should answer the same questions at the top, regardless of whether it is a module, library, config file, or example.

A reader should be able to understand **what the file does, why it exists, and where it fits** without reading its implementation.

This is documentation for humans. Keep headers concise and factual.

---

# General Format

```nix
# ============================================================================
# TYPE
#   ...
#
# PATH
#   ...
#
# PURPOSE
#   ...
#
# INPUT
#   ...
#
# OUTPUT
#   ...
#
# EXPORTS
#   ...
#
# USED BY
#   ...
#
# SEE ALSO
#   ...
#
# NOTES
#   ...
# ============================================================================
```

Sections that don't apply may simply be omitted.

---

# Section Reference

## TYPE

Describes what kind of file this is.

Typical values:

- MODULE
- LIBRARY
- SCHEMA
- CONFIG
- ENTRYPOINT
- EXAMPLE

Examples:

```text
TYPE
  MODULE
```

```text
TYPE
  LIBRARY
```

```text
TYPE
  CONFIG
```

---

## PATH

Repository-relative path.

Example:

```text
PATH
  modules/packages/default.nix
```

---

## PURPOSE

The most important field.

Explain **why this file exists**, not what every line does.

Good:

```text
PURPOSE
  Registers all package-related submodules.
```

Good:

```text
PURPOSE
  Converts config.vars.system.mountpoints into runtime mount definitions.
```

Avoid:

```text
PURPOSE
  Contains code.
```

---

## INPUT

Documents the primary inputs.

Examples:

```text
INPUT
  config.vars.packages
```

```text
INPUT
  config.vars.system.mountpoints
```

```text
INPUT
  pkgs
  lib
```

Only include the meaningful inputs, not every function argument.

---

## OUTPUT

Documents the primary outputs.

Examples:

```text
OUTPUT
  environment.systemPackages
```

```text
OUTPUT
  fileSystems
```

```text
OUTPUT
  systemd.services.*
```

---

## EXPORTS

For library files.

Example:

```text
EXPORTS
  mkPackage
  mkRegistry
```

---

## USED BY

Where this file is expected to be imported or consumed.

Examples:

```text
USED BY
  modules/default.nix
```

```text
USED BY
  modules/packages/default.nix
```

---

## SEE ALSO

Related files.

Example:

```text
SEE ALSO
  glossar/software/packages.nix
  config/software/packages.nix
```

---

## NOTES

Anything that isn't obvious.

Examples:

```text
NOTES
  Import order matters.
```

```text
NOTES
  This file intentionally contains no implementation logic.
```

```text
NOTES
  Paths are resolved during evaluation.
```

---

# Examples

## Example: Module

```nix
# ============================================================================
# TYPE
#   MODULE
#
# PATH
#   modules/packages/default.nix
#
# PURPOSE
#   Entry point for the package module. Imports all package-related
#   submodules.
#
# PROVIDES
#   config.vars.packages
#
# USED BY
#   modules/default.nix
#
# NOTES
#   Import order matters.
# ============================================================================
```

---

## Example: Library

```nix
# ============================================================================
# TYPE
#   LIBRARY
#
# PATH
#   modules/packages/lib/mk-package.nix
#
# PURPOSE
#   Helper functions for constructing package definitions.
#
# EXPORTS
#   mkPackage
#   mkOptionalPackage
#
# USED BY
#   modules/packages/*
# ============================================================================
```

---

## Example: Schema

```nix
# ============================================================================
# TYPE
#   SCHEMA
#
# PATH
#   modules/packages/default.nix
#
# PURPOSE
#   Defines the option schema for config.vars.packages.
#
# OUTPUT
#   config.vars.packages
#
# SEE ALSO
#   config/software/packages.nix
# ============================================================================
```

---

## Example: Config

```nix
# ============================================================================
# TYPE
#   CONFIG
#
# PATH
#   config/software/packages.nix
#
# PURPOSE
#   Declares the packages enabled on this machine.
#
# OUTPUT
#   config.vars.packages
#
# SEE ALSO
#   glossar/software/packages.nix
# ============================================================================
```

---

## Example: Example/Glossary

```nix
# ============================================================================
# TYPE
#   EXAMPLE
#
# PATH
#   glossar/software/packages.nix
#
# PURPOSE
#   Documents every available config.vars.packages option with
#   commented examples.
#
# NOTES
#   Never imported.
#   Purely copy-paste reference documentation.
# ============================================================================
```

---

# Guidelines

## Keep headers factual

Good:

```text
PURPOSE
  Registers package definitions.
```

Bad:

```text
PURPOSE
  Amazing package system.
```

---

## Describe intent, not implementation

Good:

```text
PURPOSE
  Creates mount definitions.
```

Bad:

```text
PURPOSE
  Loops over an attrset and calls mapAttrs.
```

Implementation belongs in the code.

---

## Keep headers short

The header should usually fit within 10 to 20 lines.

If you need multiple paragraphs, the information probably belongs in a README or glossary entry instead.

---

## Omit unused sections

Don't write empty headings.

Instead of:

```text
EXPORTS

USED BY

NOTES
```

simply remove them.

---

# Recommended Order

Always use the same order:

1. TYPE
2. PATH
3. PURPOSE
4. INPUT
5. OUTPUT
6. EXPORTS
7. USED BY
8. SEE ALSO
9. NOTES

Using the same structure everywhere makes large repositories much easier to navigate because readers immediately know where to look for specific information.
