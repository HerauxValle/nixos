"""
Permissive isolation preset: Relaxed restrictions for debugging and compatibility.

Use for: Development, legacy apps, debugging seccomp/AppArmor issues.
Trade-off: Lowest security. Only use during development/testing.
"""

PERMISSIVE = {
    "allow_tmp": True,
    "allow_var": "all",
    "allow_network": True,
    "description": "Relaxed: debugging and compatibility mode (lowest security)",
}
