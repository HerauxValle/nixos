"""
lib/apparmor/generator.py — Profile generation from SecuritySpec

String-template based (zero external dependencies).
Deterministic: same spec → same profile (always).

Philosophy: Generator is the source of truth for policy.
When apps fail, we fix the generator rules, not add special cases.
"""

from common.emit import emit
from common.sanitize import safe_name


def generate_profile(spec, service_name: str, project_name: str = "seed", include_metadata: bool = True) -> str:
    """Generate AppArmor profile from SecuritySpec.

    Uses string templates (no Jinja2, no external libs).
    Returns complete, valid profile text.
    Validates output before returning.

    Args:
        spec: SecuritySpec instance
        service_name: Service name (used in profile name)
        project_name: Project/app name (defaults to "seed")
        include_metadata: If True, add debug metadata section (v1.4.4+)

    Returns:
        Complete AppArmor profile text (ready to load)
    """
    from lib.apparmor.presets_manager import get_preset  # pragma: no cover
    from lib.apparmor.introspection import generate_metadata_section  # pragma: no cover

    # Validate inputs (security pattern)
    safe_name(service_name, "service name")
    safe_name(project_name, "project name")

    # Profile name (format: sd-{project}-{service})
    profile_name = f"sd-{project_name}-{service_name}"

    emit("log", f"[apparmor] Generating profile: {profile_name}")

    # Load preset rules
    preset = get_preset(spec.isolation_preset)

    # Build rule sections
    device_rules = _build_device_rules()
    fs_rules = _build_filesystem_rules(spec, preset)
    exec_rules = _build_execution_rules(spec)
    net_rules = _build_network_rules(spec, preset) if spec.network_enabled else ""

    # Add metadata section (v1.4.4+)
    metadata_section = ""
    if include_metadata:
        metadata_section = generate_metadata_section(spec, service_name, project_name)

    # Assemble profile (string template)
    profile = f"""{metadata_section}#include <tunables/global>

profile {profile_name} flags=(attach_disconnected,mediate_deleted) {{
  #include <abstractions/base>

  # Device access (minimal safe set)
{device_rules}

  # Filesystem rules
{fs_rules}

  # Execution rules
{exec_rules}

  # Network rules (if enabled)
{net_rules}
}}
"""

    # Validate syntax before returning
    syntax_warnings = _validate_profile_syntax(profile)
    if syntax_warnings:
        emit("warn", "AppArmor profile has syntax concerns:")
        for warning in syntax_warnings:
            emit("warn", f"  {warning}")

    emit("log", f"[apparmor] Profile generated ({len(profile)} bytes)")

    return profile


def _build_device_rules() -> str:
    """Generate minimal safe device rules.

    Conservative set: only essential character devices.
    """
    lines = [
        "  # Device access (minimal safe set)",
        "  /dev/null rw,",
        "  /dev/zero r,",
        "  /dev/urandom r,",
        "  /dev/random r,",
    ]
    return "\n".join(lines)


def _build_filesystem_rules(spec, preset: dict) -> str:
    """Generate filesystem rules from SecuritySpec.

    Combines:
    - Read-only system paths (from spec baseline)
    - Writable storage paths (from blueprint storage config)
    - Preset toggles (/tmp, /var behavior)
    - Runtime dependencies (DNS, interpreters, etc)

    Philosophy: Generator decides policy, not hardcoded elsewhere.
    When apps fail (missing /usr/lib/python3.9/**), we adjust here.
    """
    lines = []

    # Read-only system paths (safe baseline)
    lines.append("  # System read-only paths")
    for path in spec.read_only_paths:
        lines.append(f"  {path}/** r,")

    # Runtime dependencies (needed for most apps)
    lines.append("  # Runtime dependencies")
    lines.append("  /run/systemd/resolve/stub-resolv.conf r,")  # DNS resolution
    lines.append("  /etc/resolv.conf r,")  # DNS
    lines.append("  /etc/nsswitch.conf r,")  # Name service switch
    lines.append("  /etc/passwd r,")  # User info
    lines.append("  /etc/group r,")  # Group info

    # Writable storage paths (from blueprint [run]:[storage]:)
    if spec.writable_paths:
        lines.append("  # Writable storage (from blueprint)")
        for storage_key, mount_path in spec.writable_paths.items():
            lines.append(f"  {mount_path}/** rw,")

    # /tmp handling (preset-dependent)
    if preset.get("allow_tmp"):
        lines.append("  # Temporary directory (preset allows)")
        lines.append("  /tmp/** rw,")
        lines.append("  /var/tmp/** rw,")
        lines.append("  /run/** rw,")

    # /var handling (preset-dependent)
    allow_var = preset.get("allow_var", "all")
    if allow_var == "all":
        lines.append("  # /var (all, preset allows)")
        lines.append("  /var/** rw,")
    elif allow_var == "log":
        lines.append("  # /var/log only (preset restricts)")
        lines.append("  /var/log/** rw,")
    # else: allow_var == "none" → no /var access

    return "\n".join(lines)


def _build_execution_rules(spec) -> str:
    """Generate execution rules for allowed binaries.

    Lists all resolved executables + interpreters.
    Pattern: {path} rix,
    - r: read
    - i: inherit (keep existing profile)
    - x: execute
    """
    lines = ["  # Allowed executables"]

    if not spec.executables:
        lines.append("  # (no executables resolved)")
        return "\n".join(lines)

    for exe_path in spec.executables:
        lines.append(f"  {exe_path} rix,")

    return "\n".join(lines)


def _build_network_rules(spec, preset: dict) -> str:
    """Generate network rules.

    If network enabled in blueprint AND preset allows:
    - Allow inet/inet6 streams and datagrams
    - Allow unix domain sockets (IPC)

    Note: Port filtering stays in kernel iptables.
    AppArmor controls allow/deny, not specific ports.
    """
    allow_network = preset.get("allow_network", False)

    if not spec.network_enabled or not allow_network:
        return "  # Network disabled (preset or blueprint)"

    lines = ["  # Network access"]
    lines.append("  network inet stream,")
    lines.append("  network inet dgram,")
    lines.append("  network inet6 stream,")
    lines.append("  network inet6 dgram,")
    lines.append("  network unix stream,")
    lines.append("  network unix dgram,")

    return "\n".join(lines)


def _validate_profile_syntax(profile: str) -> list[str]:
    """Validate profile for common issues.

    Returns list of warnings (not errors - profile may still load).
    Warnings indicate patterns that might need review.

    Philosophy: Warn about questionable patterns, don't reject.
    Actual validation happens when kernel loads the profile.
    """
    warnings = []

    # Overly broad deny (AppArmor is deny-by-default anyway)
    if "deny /** rwkl" in profile:
        warnings.append(
            "Profile has explicit 'deny /** rwkl' (AppArmor denies by default, may be redundant)"
        )

    # Missing read rules but lots of writes (unusual)
    has_broad_write = "/** rw" in profile
    has_read_rules = "/** r" in profile or "/usr" in profile

    if has_broad_write and not has_read_rules:
        warnings.append(
            "Profile allows writes but minimal reads (unusual pattern, likely app will fail)"
        )

    # No executables
    if "rix," not in profile and "x " not in profile:
        warnings.append(
            "Profile has no executable rules (app may not start)"
        )

    return warnings
