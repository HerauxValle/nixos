"""
core/parser/processing/deps.py — deps block parser

New syntax (managers):
  pkg: curl git ca-certificates
  pip: requests flask --dev
  npm: react next --dev
  git: https://github.com/user/repo.git to=/app branch=main

Old syntax (legacy, converted to pkg:):
  curl git ca-certificates

Returns:
  [
    ("pkg", "curl git ca-certificates"),
    ("pip", "requests flask --dev"),
    ...
  ]
"""

import re


def parse_deps(raw: list[str]) -> list[tuple[str, str]]:
    """
    Parse deps into list of (manager, args) tuples.

    New syntax: 'manager: args'
    Old syntax: plain package names (converted to 'pkg:')
    """
    deps = []

    for line in raw:
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        # Check for new syntax: 'manager: args'
        if ":" in line:
            manager, _, args = line.partition(":")
            manager = manager.strip()
            args = args.strip()

            if manager and args:
                deps.append((manager, args))
            continue

        # Old syntax: space/comma-separated packages → convert to pkg: syntax
        for pkg in re.split(r"[\s,]+", line):
            pkg = pkg.strip()
            if pkg:
                # Accumulate old-style packages into a single 'pkg:' entry
                # (or add one at a time if you prefer)
                if deps and deps[-1][0] == "pkg":
                    # Append to existing pkg: entry
                    manager, existing_args = deps[-1]
                    deps[-1] = (manager, f"{existing_args} {pkg}")
                else:
                    deps.append(("pkg", pkg))

    return deps