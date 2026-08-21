"""
Default isolation preset: Balanced security and usability.

Use for: Most containers, general-purpose workloads.
Trade-off: Reasonable security without excessive restrictions.
"""

DEFAULT = {
    "allow_tmp": True,
    "allow_var": "all",
    "allow_network": True,
    "description": "Balanced: allow /tmp, /var, networking (default for most apps)",
}
