"""
Strict isolation preset: Deny everything except explicitly required resources.

Use for: High-security containers, untrusted workloads, sensitive data processing.
Trade-off: Apps may break (need /tmp, /var access). Fix by adjusting generator.
"""

STRICT = {
    "allow_tmp": False,
    "allow_var": "none",
    "allow_network": False,
    "description": "Deny everything except explicitly required resources (highest security)",
}
