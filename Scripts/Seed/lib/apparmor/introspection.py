"""
lib/apparmor/introspection.py — Profile introspection and debugging support

Features:
  1. Enhanced profile comments with debug guide
  2. Store profiles with metadata for caching + versioning
  3. Detect AppArmor violations from audit logs
  4. Generate remediation suggestions

Helps users debug why sandboxing fails instead of just watching app die.
"""

import os
import hashlib
import json
from datetime import datetime
from pathlib import Path
from common.emit import emit
from common.errors import error


# Profile cache directory
PROFILE_CACHE_DIR = "/var/lib/seed/apparmor"


def generate_metadata_section(spec, service_name: str, project_name: str) -> str:
    """Generate metadata comment block for profile.

    Includes:
    - Profile name and generation timestamp
    - Blueprint and preset info
    - SecuritySpec dump (for debugging)
    - Debug guide with remediation hints

    Args:
        spec: SecuritySpec instance
        service_name: Service name
        project_name: Project name

    Returns:
        Metadata comment block (multiple lines)
    """
    profile_name = f"sd-{project_name}-{service_name}"
    now = datetime.utcnow().isoformat() + "Z"

    metadata = f"""# AppArmor Profile: {profile_name}
# Generated: {now}
# Blueprint: {project_name}:{service_name}
# Preset: {spec.isolation_preset}
#
# SecuritySpec:
#   - entrypoint: {spec.entrypoint_binary}
#   - executables: {len(spec.executables)} binaries
#   - writable_paths: {list(spec.writable_paths.keys())}
#   - network_enabled: {spec.network_enabled}
#   - allow_tmp: {spec.allow_tmp}
#   - allow_var: {spec.allow_var}
#
# Debug Guide:
# - If "Permission denied reading /path/to/file":
#   1. Check if path is in writable_paths or read_only_paths above
#   2. If missing: add to [run]:[storage]: in blueprint
#   3. Or improve lib/apparmor/spec.py read_only_paths baseline
#
# - If "Operation not permitted" (syscall denied):
#   1. Profile doesn't restrict syscalls (that's lib/seccomp/profile.py)
#   2. Check /var/log/audit/audit.log for apparmor= violations:
#      sudo tail -50 /var/log/audit/audit.log | grep "apparmor="
#   3. Report at: https://github.com/anthropics/sd-init/issues
#
# - To reload profile manually:
#   sudo apparmor_parser -r {profile_name}
#
"""

    return metadata


def compute_spec_hash(spec) -> str:
    """Compute deterministic hash of SecuritySpec.

    Used for profile caching: if spec unchanged → reuse cached profile.

    Args:
        spec: SecuritySpec instance

    Returns:
        Hex hash (first 8 chars sufficient for uniqueness)
    """
    # Serialize spec fields in deterministic order
    spec_repr = json.dumps(
        {
            "entrypoint": spec.entrypoint_binary,
            "executables": sorted(spec.executables),
            "writable_paths": sorted(spec.writable_paths.items()),
            "read_only_paths": sorted(spec.read_only_paths),
            "network_enabled": spec.network_enabled,
            "allow_tmp": spec.allow_tmp,
            "allow_var": spec.allow_var,
            "isolation_preset": spec.isolation_preset,
        },
        sort_keys=True,
        separators=(",", ":"),
    )

    hash_obj = hashlib.sha256(spec_repr.encode("utf-8"))
    return hash_obj.hexdigest()[:8]


def store_profile(profile_text: str, service_name: str, spec, project_name: str = "seed"):
    """Store generated profile on disk with metadata.

    Stores at: /var/lib/seed/apparmor/{service}.profile.{hash}
    Includes metadata: SecuritySpec hash, generation timestamp, preset version

    Args:
        profile_text: Generated AppArmor profile
        service_name: Service name
        spec: SecuritySpec instance (for hashing)
        project_name: Project name (default "seed")
    """
    try:
        # Create cache directory if needed
        Path(PROFILE_CACHE_DIR).mkdir(parents=True, exist_ok=True)

        # Compute spec hash for caching
        spec_hash = compute_spec_hash(spec)

        # Profile filename: {service}.profile.{hash}
        profile_filename = f"{service_name}.profile.{spec_hash}"
        profile_path = os.path.join(PROFILE_CACHE_DIR, profile_filename)

        # Store profile
        with open(profile_path, "w") as f:
            f.write(profile_text)

        # Store metadata alongside
        metadata = {
            "service": service_name,
            "project": project_name,
            "preset": spec.isolation_preset,
            "spec_hash": spec_hash,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "profile_path": profile_path,
        }

        metadata_path = profile_path + ".meta.json"
        with open(metadata_path, "w") as f:
            json.dump(metadata, f, indent=2)

        emit("log", f"[introspection] Stored profile at {profile_path}")
        emit("log", f"[introspection] Metadata at {metadata_path}")

    except (OSError, PermissionError) as e:
        emit("warn", f"[introspection] Could not store profile: {e}")
        # Graceful fallback: profile still works, just not cached


def detect_violations_in_logs(profile_name: str) -> list[dict]:
    """Parse /var/log/audit/audit.log for AppArmor violations.

    Extracts denied operations matching profile name.
    Returns structured info for remediation suggestions.

    Args:
        profile_name: Profile name to search for

    Returns:
        List of violation dicts: {"denied_access", "name", "profile"}
    """
    violations = []
    audit_log = "/var/log/audit/audit.log"

    if not os.path.exists(audit_log):
        emit("log", "[introspection] No audit log (normal on non-SELinux systems)")
        return violations

    try:
        with open(audit_log, "r") as f:
            for line in f:
                # Look for apparmor= violations
                if "apparmor=" not in line or profile_name not in line:
                    continue

                # Parse: apparmor="DENIED" operation="open" name="/tmp/..." profile="sd-..."
                # This is a simplified parser; real one would use proper parsing

                violation = {}
                for part in line.split():
                    if part.startswith('apparmor="'):
                        violation["status"] = part.split('"')[1]
                    elif part.startswith('operation="'):
                        violation["operation"] = part.split('"')[1]
                    elif part.startswith('name="'):
                        violation["path"] = part.split('"')[1]
                    elif part.startswith('profile="'):
                        violation["profile"] = part.split('"')[1]

                if violation.get("status") == "DENIED":
                    violations.append(violation)

    except (PermissionError, OSError) as e:
        emit("log", f"[introspection] Could not read audit log: {e} (need sudo)")

    return violations


def suggest_remediation(violation: dict, spec) -> list[str]:
    """Generate remediation suggestions for a violation.

    Args:
        violation: Violation dict from detect_violations_in_logs()
        spec: SecuritySpec instance (context for suggestion)

    Returns:
        List of suggested remediation commands/steps
    """
    suggestions = []

    operation = violation.get("operation")
    path = violation.get("path")

    if not path:
        return ["Unable to determine path from violation"]

    # Suggestion 1: Add missing path to writable_paths in blueprint
    if operation in ("open", "write"):
        suggestions.append(
            f"If {path} needs write access, add to blueprint [run]:[storage]:\n"
            f"  data = \"{path}\""
        )

    # Suggestion 2: Check read-only baseline
    if operation in ("open", "read"):
        suggestions.append(
            f"If {path} needs read access, check if it should be in spec.py read_only_paths baseline"
        )

    # Suggestion 3: Check AppArmor rules
    suggestions.append(
        f"Check generated profile for {path} rules, see /var/lib/seed/apparmor/"
    )

    return suggestions
