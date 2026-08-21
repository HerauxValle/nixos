"""
lib/apparmor/spec.py — SecuritySpec data model

Normalized internal representation for security constraints.
Can serve AppArmor (and future backends: Landlock, BPF, etc).

All fields validated at construction. No silent failures.
"""

from dataclasses import dataclass, field
import os
from common.sanitize import safe_name, safe_path_within
from common.errors import error
from common.emit import emit


@dataclass
class SecuritySpec:
    """Normalized security IR from blueprint.

    Represents runtime security requirements independent of backend.
    All fields validated at construction.
    """
    base_path: str                      # container rootfs mount (e.g., /var/lib/seed/...)
    entrypoint_binary: str              # resolved binary path (e.g., /usr/bin/python3)
    entrypoint_args: list[str]          # args after binary (e.g., ['/app/main.py'])
    executables: list[str] = field(default_factory=list)  # all resolved paths
    writable_paths: dict[str, str] = field(default_factory=dict)  # storage → mount_path
    read_only_paths: list[str] = field(default_factory=list)  # system defaults
    network_enabled: bool = False       # from run.config.port
    allow_tmp: bool = True              # from preset
    allow_var: str = "all"              # all | log | none (from preset)
    isolation_preset: str = "default"   # strict | default | permissive

    def validate(self) -> list[str]:
        """Validate all fields. Returns list of errors (empty = valid)."""
        errors = []

        # Validate preset
        if self.isolation_preset not in ("strict", "default", "permissive"):
            errors.append(f"Invalid preset: {self.isolation_preset} (must be strict|default|permissive)")

        # Validate allow_var
        if self.allow_var not in ("all", "log", "none"):
            errors.append(f"Invalid allow_var: {self.allow_var} (must be all|log|none)")

        # Validate paths (no traversal, must be absolute)
        all_paths = (
            [self.base_path, self.entrypoint_binary]
            + self.executables
            + list(self.writable_paths.values())
            + self.read_only_paths
        )

        for path in all_paths:
            if not path:
                continue

            # No path traversal
            if ".." in path or path.startswith("~"):
                errors.append(f"Path traversal detected: {path}")

            # Must be absolute
            if not path.startswith("/"):
                errors.append(f"Path must be absolute: {path}")

        # Validate entrypoint
        if self.entrypoint_binary and "/" not in self.entrypoint_binary:
            errors.append(f"Entrypoint must be absolute path: {self.entrypoint_binary}")

        # Validate executable list is not empty
        if not self.executables and self.entrypoint_binary:
            errors.append("Executable list empty but entrypoint specified")

        return errors

    @classmethod
    def from_blueprint(
        cls,
        service,
        mount_path: str,
        preset: str = "default",
    ) -> "SecuritySpec":
        """Create SecuritySpec from parsed blueprint service.

        Validates all inputs using safe_path_within(), safe_name().
        Resolves binaries via resolver module.
        Raises error() on invalid config.

        Args:
            service: Parsed Service object from blueprint
            mount_path: Container rootfs mount path (e.g., /var/lib/seed/...)
            preset: Isolation level (strict|default|permissive)

        Returns:
            SecuritySpec instance (validated)

        Raises:
            SDError on validation failure
        """
        from lib.apparmor.resolver import resolve_binaries
        from lib.apparmor.presets_manager import get_preset

        # Validate inputs (pattern from common/sanitize.py)
        try:
            safe_name(service.name, "service name")
            safe_path_within("/", mount_path.lstrip("/"), "container mount path")
            safe_name(preset, "preset")
        except Exception as e:
            error("INVALID_SECSPEC_INPUT", str(e))

        emit("log", f"[apparmor] Creating SecuritySpec for {service.name} (preset={preset})")

        # Load preset rules
        preset_dict = get_preset(preset)

        # Extract entrypoint (split binary from args)
        entrypoint_full = service.run.config.get("entrypoint", "")
        if entrypoint_full:
            parts = entrypoint_full.split()
            entrypoint_binary = parts[0]
            entrypoint_args = parts[1:] if len(parts) > 1 else []
        else:
            entrypoint_binary = ""
            entrypoint_args = []

        # Resolve binaries (includes shebang detection)
        try:
            executables = resolve_binaries(service, mount_path)
        except Exception as e:
            error("BINARY_RESOLUTION_FAILED", f"Could not resolve binaries: {e}")

        # Get storage mounts
        writable_paths = service.run.storage or {}

        # Read-only system paths (safe baseline)
        # Includes paths for Python, Node, Ruby interpreters + common runtime files
        read_only_paths = [
            # Core system binaries
            "/usr/lib",
            "/usr/lib64",
            "/usr/bin",
            "/usr/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/lib",
            "/lib64",
            "/bin",
            "/sbin",
            # Configuration
            "/etc",
            # Runtime info
            "/proc",
            "/sys/devices",
            "/sys/class",
            "/dev/pts",
            # Interpreter-specific stdlib (Python, Ruby, etc)
            # These are caught by /usr/lib/** but listed explicitly for clarity
            "/usr/lib/python3*",
            "/usr/lib/python2*",
            "/usr/lib/ruby*",
            "/usr/lib/node*",
            "/usr/lib/perl*",
            # Locale and timezone data
            "/usr/share/locale",
            "/usr/share/zoneinfo",
            # CA certificates (for TLS)
            "/etc/ssl",
            "/usr/share/ca-certificates",
        ]

        # Create spec
        spec = cls(
            base_path=mount_path,
            entrypoint_binary=entrypoint_binary,
            entrypoint_args=entrypoint_args,
            executables=executables,
            writable_paths=writable_paths,
            read_only_paths=read_only_paths,
            network_enabled=bool(service.run.config.get("port")),
            allow_tmp=preset_dict.get("allow_tmp", True),
            allow_var=preset_dict.get("allow_var", "all"),
            isolation_preset=preset,
        )

        # Validate
        errors = spec.validate()
        if errors:
            error("INVALID_SECSPEC", "SecuritySpec validation failed", *errors)

        emit("log", f"[apparmor] SecuritySpec valid: {len(spec.executables)} executables, "
                    f"{len(spec.writable_paths)} writable paths")

        return spec
