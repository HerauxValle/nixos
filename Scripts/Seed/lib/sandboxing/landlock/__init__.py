"""
lib/sandboxing/landlock — Unprivileged filesystem sandboxing via Landlock (Linux 5.13+)

Landlock is a non-root namespace-based access control system.
Restrictions apply to process + children, no privilege escalation required.

Architecture:
  SecuritySpec
    ↓
  build_rules_from_spec() → LandlockRule list
    ↓
  LandlockEnforcer.restrict() → Apply via prctl()

When AppArmor unavailable, Landlock provides fallback confinement.
"""

from lib.sandboxing.landlock.enforcer import LandlockEnforcer
from lib.sandboxing.landlock.compat import check_landlock_available, get_kernel_version
from lib.sandboxing.landlock.rules import build_rules_from_spec, LandlockRule

__all__ = [
    "LandlockEnforcer",
    "check_landlock_available",
    "get_kernel_version",
    "build_rules_from_spec",
    "LandlockRule",
]
