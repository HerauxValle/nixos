"""
lib/sandboxing — Pluggable security enforcement backends

Architecture:
  SecuritySpec (normalized IR)
    ↓
  backend selection (AppArmor > Landlock > none)
    ↓
  backend-specific enforcement (AppArmorGenerator, LandlockEnforcer, etc)
    ↓
  Runtime load at container start

All backends derive from single SecuritySpec → no duplication, consistent policy.
Graceful fallback: best available enforcement, no errors.
"""
