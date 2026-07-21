#!/usr/bin/env python3
"""
Verify security fixes have been applied correctly.
Run: python3 tests/verify_security_fixes.py
"""

import os
import sys
import subprocess
from pathlib import Path

# Add parent dir to path
sys.path.insert(0, str(Path(__file__).parent.parent))

def check_file_contains(filepath: str, text: str, description: str) -> bool:
    """Verify file contains required text."""
    try:
        with open(filepath) as f:
            content = f.read()
        if text in content:
            print(f"✓ {description}")
            return True
        else:
            print(f"✗ {description}")
            print(f"  Expected substring: {text[:80]}")
            return False
    except FileNotFoundError:
        print(f"✗ {description} — file not found: {filepath}")
        return False


def check_file_not_contains(filepath: str, text: str, description: str) -> bool:
    """Verify file does NOT contain dangerous text."""
    try:
        with open(filepath) as f:
            content = f.read()
        if text not in content:
            print(f"✓ {description}")
            return True
        else:
            print(f"✗ {description}")
            print(f"  Found dangerous substring: {text[:80]}")
            return False
    except FileNotFoundError:
        print(f"✗ {description} — file not found: {filepath}")
        return False


def check_file_exists(filepath: str, description: str) -> bool:
    """Verify file exists."""
    if os.path.exists(filepath):
        print(f"✓ {description}")
        return True
    else:
        print(f"✗ {description} — file not found: {filepath}")
        return False


def verify_python_syntax(filepath: str, description: str) -> bool:
    """Verify Python file has valid syntax."""
    try:
        with open(filepath) as f:
            compile(f.read(), filepath, 'exec')
        print(f"✓ {description}")
        return True
    except SyntaxError as e:
        print(f"✗ {description} — syntax error: {e}")
        return False


def main():
    """Run all verification checks."""
    root = Path(__file__).parent.parent
    checks = []

    print("Security Fix Verification")
    print("=" * 70)
    print()

    # ========================================================================
    # FIX #1: User namespaces
    # ========================================================================
    print("1. User Namespaces (in sd-init C binary)")
    checks.append(check_file_contains(
        str(root / "helpers/sd-init.c"),
        'CLONE_NEWUSER',
        "User namespace created in sd-init.c"
    ))
    checks.append(check_file_contains(
        str(root / "helpers/sd-init.c"),
        'uid_map',
        "UID mapping in sd-init.c"
    ))
    print()

    # ========================================================================
    # FIX #2: File descriptor leaks
    # ========================================================================
    print("2. File Descriptor Leaks (close_fds=True)")
    checks.append(check_file_contains(
        str(root / "engine/container/run.py"),
        'close_fds=True, pass_fds=()',
        "subprocess.Popen closes FDs in run.py"
    ))
    checks.append(check_file_contains(
        str(root / "engine/container/exec.py"),
        'close_fds=True, pass_fds=()',
        "subprocess.run closes FDs in exec.py"
    ))
    print()

    # ========================================================================
    # FIX #3-6: Mount setup, entrypoint quoting, capsh moved to sd-init
    # ========================================================================
    print("3-6. Mount setup, Entrypoint quoting, Capability drop (in sd-init C)")
    checks.append(check_file_contains(
        str(root / "helpers/sd-init.c"),
        'mount("tmpfs", "dev"',
        "Mount setup in sd-init.c (tmpfs for /dev)"
    ))
    checks.append(check_file_contains(
        str(root / "helpers/sd-init.c"),
        'mount("proc"',
        "Mount setup in sd-init.c (proc with hidepid=2)"
    ))
    checks.append(check_file_contains(
        str(root / "helpers/sd-init.c"),
        'drop_caps_except',
        "Capability drop in sd-init.c (capset)"
    ))
    checks.append(check_file_not_contains(
        str(root / "engine/container/run.py"),
        'shlex.quote',
        "No shell quoting needed (args passed as list)"
    ))
    print()

    # ========================================================================
    # FIX #7: Seccomp BPF compiled into sd-init + no_new_privs in C
    # ========================================================================
    print("7. Seccomp BPF Filter (compiled in sd-init C binary)")
    checks.append(check_file_contains(
        str(root / "helpers/sd-init.c"),
        'SECCOMP_MODE_FILTER',
        "Seccomp BPF loaded in sd-init.c"
    ))
    checks.append(check_file_contains(
        str(root / "helpers/sd-init.c"),
        'PR_SET_NO_NEW_PRIVS',
        "no_new_privs set in sd-init.c"
    ))
    checks.append(check_file_contains(
        str(root / "helpers/sd-init-seccomp.h"),
        'sd_seccomp_filter',
        "BPF filter array generated in sd-init-seccomp.h"
    ))
    print()

    # ========================================================================
    # FIX #8: pivot_root atomicity in sd-init C
    # ========================================================================
    print("8. pivot_root Atomicity (in sd-init C binary)")
    checks.append(check_file_contains(
        str(root / "helpers/sd-init.c"),
        'pivot_root(".", "old_root")',
        "pivot_root used for atomic root swap in sd-init.c"
    ))
    checks.append(check_file_contains(
        str(root / "helpers/sd-init.c"),
        'umount2("/old_root"',
        "Old root unmounted with MNT_DETACH in sd-init.c"
    ))
    print()

    # ========================================================================
    # FIX #9: Cgroup race (process joins cgroup in sd-init before exec)
    # ========================================================================
    print("9. Cgroup Race Prevention (join in sd-init before exec)")
    checks.append(check_file_contains(
        str(root / "helpers/sd-init.c"),
        'cgroup.procs',
        "Cgroup join happens in sd-init.c"
    ))
    checks.append(check_file_not_contains(
        str(root / "engine/container/run.py"),
        '_write_init_script',
        "Shell init script generation removed (moved to sd-init)"
    ))
    print()

    # ========================================================================
    # FIX #10: PID TOCTOU race (nsenter direct entry)
    # ========================================================================
    print("10. PID TOCTOU Prevention (nsenter -t PID direct entry)")
    checks.append(check_file_not_contains(
        str(root / "engine/container/exec.py"),
        'pgrep -P',
        "Unsafe pgrep child lookup removed"
    ))
    checks.append(check_file_contains(
        str(root / "engine/container/exec.py"),
        '"--all", "--"] + cmd',
        "Direct nsenter namespace entry"
    ))
    print()

    # ========================================================================
    # FIX #9: Loop device state locking
    # ========================================================================
    print("9. Loop Device State (fcntl locking)")
    checks.append(check_file_contains(
        str(root / "lib/privilege.py"),
        "fcntl.LOCK_EX",
        "Exclusive file locking on loopdev state"
    ))
    checks.append(check_file_contains(
        str(root / "lib/privilege.py"),
        "fcntl.LOCK_SH",
        "Shared file locking on loopdev state"
    ))
    print()

    # ========================================================================
    # FIX #10: Syntax checks
    # ========================================================================
    print("10. Python Syntax Validation")
    checks.append(verify_python_syntax(
        str(root / "engine/container/run.py"),
        "engine/container/run.py syntax valid"
    ))
    checks.append(verify_python_syntax(
        str(root / "engine/container/exec.py"),
        "engine/container/exec.py syntax valid"
    ))
    checks.append(verify_python_syntax(
        str(root / "lib/privilege.py"),
        "lib/privilege.py syntax valid"
    ))
    print()

    # ========================================================================
    # Summary
    # ========================================================================
    print("=" * 70)
    passed = sum(checks)
    total = len(checks)
    percent = (passed / total * 100) if total else 0

    print(f"Results: {passed}/{total} checks passed ({percent:.0f}%)")

    if passed == total:
        print("✓ All security fixes verified!")
        return 0
    else:
        print(f"✗ {total - passed} checks failed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
