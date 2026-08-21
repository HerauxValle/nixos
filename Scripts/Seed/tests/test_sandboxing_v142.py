"""
tests/test_sandboxing_v142.py — Test v1.4.2-v1.4.4 features

Tests:
  1. Landlock kernel detection and rule generation (v1.4.2)
  2. Seccomp+AppArmor synergy (v1.4.3)
  3. Profile introspection and metadata (v1.4.4)
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from lib.sandboxing.landlock.compat import check_landlock_available, get_kernel_version
from lib.sandboxing.landlock.rules import build_rules_from_spec, LandlockRule, LANDLOCK_ACCESS_FS_READ_FILE
from lib.sandboxing.backends import BackendSelection
from lib.seccomp.profile import get_restricted_syscalls
from lib.apparmor.introspection import (
    compute_spec_hash, generate_metadata_section, detect_violations_in_logs
)
from lib.apparmor.spec import SecuritySpec


def test_landlock_kernel_detection():
    """Test Landlock kernel availability detection."""
    print("\n[TEST] Landlock kernel detection...")

    # This will return False on systems < 5.13 or without Landlock
    # Just verify it doesn't crash
    try:
        result = check_landlock_available()
        print(f"  ✓ Landlock available: {result}")
        assert isinstance(result, bool)
    except Exception as e:
        print(f"  ✗ Error: {e}")
        raise


def test_kernel_version_parsing():
    """Test kernel version extraction."""
    print("\n[TEST] Kernel version parsing...")

    try:
        version = get_kernel_version()
        if version:
            print(f"  ✓ Kernel version: {version[0]}.{version[1]}.{version[2]}")
            assert len(version) == 3
            assert all(isinstance(v, int) for v in version)
        else:
            print("  ✓ Could not parse kernel version (acceptable)")
    except Exception as e:
        print(f"  ✗ Error: {e}")
        raise


def test_landlock_rules_generation():
    """Test SecuritySpec → Landlock rule mapping."""
    print("\n[TEST] Landlock rules generation...")

    # Create minimal SecuritySpec
    spec = SecuritySpec(
        base_path="/var/lib/seed/container1",
        entrypoint_binary="/usr/bin/python3",
        entrypoint_args=["/app/main.py"],
        executables=["/usr/bin/python3", "/usr/bin/python3.11"],
        writable_paths={"data": "/data", "logs": "/logs"},
        read_only_paths=["/usr/lib", "/usr/bin", "/etc"],
        network_enabled=True,
        allow_tmp=True,
        allow_var="all",
        isolation_preset="default",
    )

    try:
        rules = build_rules_from_spec(spec)
        print(f"  ✓ Generated {len(rules)} rules")

        # Verify structure
        assert len(rules) > 0
        for rule in rules[:3]:
            assert isinstance(rule, LandlockRule)
            assert rule.path.startswith("/")
            assert rule.access > 0
            print(f"    - {rule}")

    except Exception as e:
        print(f"  ✗ Error: {e}")
        raise


def test_seccomp_restrictions_network_disabled():
    """Test seccomp+AppArmor synergy: network disabled."""
    print("\n[TEST] Seccomp restrictions (network disabled)...")

    # Create spec with network disabled
    spec = SecuritySpec(
        base_path="/var/lib/seed/container1",
        entrypoint_binary="/usr/bin/python3",
        entrypoint_args=["/app/main.py"],
        executables=["/usr/bin/python3"],
        writable_paths={},
        read_only_paths=["/usr/lib", "/usr/bin"],
        network_enabled=False,  # Disabled!
        allow_tmp=True,
        isolation_preset="strict",
    )

    try:
        restricted = get_restricted_syscalls(spec)
        print(f"  ✓ Restricted {len(restricted)} syscalls when network disabled")

        # Verify network syscalls are restricted
        network_syscalls = {"socket", "connect", "bind", "listen", "sendto"}
        assert network_syscalls.issubset(restricted), "Network syscalls should be restricted"

        for syscall in list(restricted)[:5]:
            print(f"    - {syscall}")

    except Exception as e:
        print(f"  ✗ Error: {e}")
        raise


def test_seccomp_restrictions_network_enabled():
    """Test seccomp+AppArmor synergy: network enabled."""
    print("\n[TEST] Seccomp restrictions (network enabled)...")

    # Create spec with network enabled
    spec = SecuritySpec(
        base_path="/var/lib/seed/container1",
        entrypoint_binary="/usr/bin/python3",
        entrypoint_args=["/app/main.py"],
        executables=["/usr/bin/python3"],
        writable_paths={},
        read_only_paths=["/usr/lib", "/usr/bin"],
        network_enabled=True,  # Enabled!
        allow_tmp=True,
        isolation_preset="default",
    )

    try:
        restricted = get_restricted_syscalls(spec)
        print(f"  ✓ Restricted {len(restricted)} syscalls when network enabled")

        # Verify network syscalls are NOT restricted
        network_syscalls = {"socket", "connect", "bind", "listen", "sendto"}
        overlap = network_syscalls.intersection(restricted)
        assert not overlap, f"Network syscalls should NOT be restricted, but got: {overlap}"

        print("    ✓ Network syscalls allowed (expected)")

    except Exception as e:
        print(f"  ✗ Error: {e}")
        raise


def test_spec_hashing():
    """Test deterministic SecuritySpec hashing for caching."""
    print("\n[TEST] SecuritySpec hashing...")

    spec1 = SecuritySpec(
        base_path="/var/lib/seed/container1",
        entrypoint_binary="/usr/bin/python3",
        entrypoint_args=["/app/main.py"],
        executables=["/usr/bin/python3"],
        writable_paths={"data": "/data"},
        read_only_paths=["/usr/lib"],
        network_enabled=True,
        allow_tmp=True,
        isolation_preset="default",
    )

    spec2 = SecuritySpec(
        base_path="/var/lib/seed/container1",
        entrypoint_binary="/usr/bin/python3",
        entrypoint_args=["/app/main.py"],
        executables=["/usr/bin/python3"],
        writable_paths={"data": "/data"},
        read_only_paths=["/usr/lib"],
        network_enabled=True,
        allow_tmp=True,
        isolation_preset="default",
    )

    spec3 = SecuritySpec(
        base_path="/var/lib/seed/container1",
        entrypoint_binary="/usr/bin/python3",
        entrypoint_args=["/app/main.py"],
        executables=["/usr/bin/python3"],
        writable_paths={"data": "/data"},
        read_only_paths=["/usr/lib"],
        network_enabled=False,  # Different!
        allow_tmp=True,
        isolation_preset="default",
    )

    try:
        hash1 = compute_spec_hash(spec1)
        hash2 = compute_spec_hash(spec2)
        hash3 = compute_spec_hash(spec3)

        print(f"  ✓ Hash1: {hash1}")
        print(f"  ✓ Hash2: {hash2}")
        print(f"  ✓ Hash3: {hash3}")

        # Same specs → same hash (deterministic)
        assert hash1 == hash2, "Identical specs should have identical hashes"
        # Different specs → different hash
        assert hash1 != hash3, "Different specs should have different hashes"

        print("    ✓ Hashing is deterministic and differentiating")

    except Exception as e:
        print(f"  ✗ Error: {e}")
        raise


def test_metadata_generation():
    """Test profile metadata section generation."""
    print("\n[TEST] Profile metadata generation...")

    spec = SecuritySpec(
        base_path="/var/lib/seed/container1",
        entrypoint_binary="/usr/bin/python3",
        entrypoint_args=["/app/main.py"],
        executables=["/usr/bin/python3"],
        writable_paths={"data": "/data"},
        read_only_paths=["/usr/lib"],
        network_enabled=True,
        allow_tmp=True,
        isolation_preset="default",
    )

    try:
        metadata = generate_metadata_section(spec, "myapp", "myproject")

        print(f"  ✓ Generated metadata ({len(metadata)} bytes)")

        # Verify structure
        assert "AppArmor Profile: sd-myproject-myapp" in metadata
        assert "Generated:" in metadata
        assert "Blueprint: myproject:myapp" in metadata
        assert "Preset: default" in metadata
        assert "Debug Guide:" in metadata
        assert "/var/log/audit/audit.log" in metadata

        print("    ✓ Metadata includes all required sections")

    except Exception as e:
        print(f"  ✗ Error: {e}")
        raise


def test_backend_selection():
    """Test backend selection logic."""
    print("\n[TEST] Backend selection...")

    try:
        # Should return one of: "apparmor", "landlock", "none"
        backend = BackendSelection.select(None)  # None as spec (just selection logic)

        print(f"  ✓ Selected backend: {backend}")
        assert backend in ["apparmor", "landlock", "none"]

    except Exception as e:
        print(f"  ✗ Error: {e}")
        raise


if __name__ == "__main__":
    print("="*60)
    print("v1.4.2-v1.4.4 Sandboxing Tests")
    print("="*60)

    try:
        test_landlock_kernel_detection()
        test_kernel_version_parsing()
        test_landlock_rules_generation()
        test_seccomp_restrictions_network_disabled()
        test_seccomp_restrictions_network_enabled()
        test_spec_hashing()
        test_metadata_generation()
        test_backend_selection()

        print("\n" + "="*60)
        print("✓ ALL TESTS PASSED")
        print("="*60)

    except Exception as e:
        print("\n" + "="*60)
        print(f"✗ TEST FAILED: {e}")
        print("="*60)
        sys.exit(1)
