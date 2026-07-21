"""
lib/apparmor/presets/ — Isolation level definitions

Three presets with different security/usability tradeoffs:
- strict: Deny everything except explicit rules
- default: Balanced (allow /tmp, /var, networking)
- permissive: Relaxed (debugging, compatibility mode)
"""
