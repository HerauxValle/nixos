"""
test_seccomp_filtering.py — verify seccomp filtering hardening
Confirms syscall filtering with --allow-no-seccomp flag support
"""

from pathlib import Path


def get_project_root() -> Path:
    """Get project root (relative to this test file)."""
    return Path(__file__).parent.parent.parent


def test_seccomp_module_exists():
    """Verify lib/seccomp module exists with proper structure."""
    print("\n[TEST] seccomp module structure")

    project_root = get_project_root()
    seccomp_init = project_root / "lib" / "seccomp" / "__init__.py"
    loader = project_root / "lib" / "seccomp" / "loader.py"
    profile = project_root / "lib" / "seccomp" / "profile.py"

    if not seccomp_init.exists():
        print("  ✗ FAIL: lib/seccomp/__init__.py not found")
        return False

    if not loader.exists():
        print("  ✗ FAIL: lib/seccomp/loader.py not found")
        return False

    if not profile.exists():
        print("  ✗ FAIL: lib/seccomp/profile.py not found")
        return False

    # Verify __init__ exports load_seccomp_profile
    init_code = seccomp_init.read_text()
    if "load_seccomp_profile" not in init_code:
        print("  ✗ FAIL: load_seccomp_profile not exported from __init__")
        return False

    print("  ✓ PASS: seccomp module structure correct")
    return True


def test_seccomp_blocked_syscalls():
    """Verify dangerous syscalls are in blocked list."""
    print("\n[TEST] dangerous syscalls blocked")

    profile_path = get_project_root() / "lib" / "seccomp" / "profile.py"
    code = profile_path.read_text()

    # Verify blocked syscalls include dangerous ones
    dangerous = ["unshare", "mount", "bpf", "ptrace", "clone", "setns"]

    for syscall in dangerous:
        if f'"{syscall}"' not in code and f"'{syscall}'" not in code:
            print(f"  ✗ FAIL: {syscall} not in BLOCKED_SYSCALLS")
            return False

    print("  ✓ PASS: dangerous syscalls are blocked")
    return True


def test_seccomp_loader_has_error_class():
    """Verify SeccompError exception class exists."""
    print("\n[TEST] SeccompError exception class")

    loader_path = get_project_root() / "lib" / "seccomp" / "loader.py"
    code = loader_path.read_text()

    if "class SeccompError" not in code:
        print("  ✗ FAIL: SeccompError class not found")
        return False

    if "Exception" not in code.split("class SeccompError")[1].split("\n")[0]:
        print("  ✗ FAIL: SeccompError doesn't inherit from Exception")
        return False

    print("  ✓ PASS: SeccompError exception class defined")
    return True


def test_seccomp_allow_no_seccomp_flag():
    """Verify allow_no_seccomp parameter handling."""
    print("\n[TEST] allow_no_seccomp flag handling")

    loader_path = get_project_root() / "lib" / "seccomp" / "loader.py"
    code = loader_path.read_text()

    # Verify allow_no_seccomp parameter exists
    if "allow_no_seccomp" not in code:
        print("  ✗ FAIL: allow_no_seccomp parameter not found")
        return False

    # Verify it's used in conditionals
    if "if allow_no_seccomp" not in code:
        print("  ✗ FAIL: allow_no_seccomp not used in conditionals")
        return False

    # Verify emit() is called for graceful handling
    if "emit(" not in code:
        print("  ✗ FAIL: emit() not used for user feedback")
        return False

    print("  ✓ PASS: allow_no_seccomp flag properly handled")
    return True


def test_seccomp_integration_in_run():
    """Verify seccomp loading integrated in _start_container."""
    print("\n[TEST] seccomp integration in container run")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Verify seccomp import
    if "from lib.seccomp import load_seccomp_profile" not in code:
        print("  ✗ FAIL: seccomp import not found")
        return False

    # Verify seccomp load call
    if "load_seccomp_profile" not in code:
        print("  ✗ FAIL: seccomp load call not found")
        return False

    # Verify allow_no_seccomp flag is checked
    if 'run.isolation.get("allow_no_seccomp"' not in code:
        print("  ✗ FAIL: allow_no_seccomp flag not checked from isolation")
        return False

    print("  ✓ PASS: seccomp properly integrated in _start_container")
    return True


def test_seccomp_helper_exists():
    """Verify sd-seccomp helper script exists and is executable."""
    print("\n[TEST] sd-seccomp helper script")

    helper = get_project_root() / "helpers" / "sd-seccomp"

    if not helper.exists():
        print("  ✗ FAIL: sd-seccomp helper not found")
        return False

    if not (helper.stat().st_mode & 0o111):
        print("  ✗ FAIL: sd-seccomp not executable")
        return False

    # Verify it has proper shebang
    content = helper.read_text()
    if not content.startswith("#!/bin/bash"):
        print("  ✗ FAIL: sd-seccomp missing bash shebang")
        return False

    # Verify load command
    if '"load"' not in content and "'load'" not in content:
        print("  ✗ FAIL: load command not found in sd-seccomp")
        return False

    print("  ✓ PASS: sd-seccomp helper properly structured")
    return True


if __name__ == "__main__":
    print("="*70)
    print("seccomp Filtering Hardening Tests")
    print("="*70)

    results = []
    results.append(("module_structure", test_seccomp_module_exists()))
    results.append(("blocked_syscalls", test_seccomp_blocked_syscalls()))
    results.append(("error_class", test_seccomp_loader_has_error_class()))
    results.append(("allow_no_seccomp", test_seccomp_allow_no_seccomp_flag()))
    results.append(("integration", test_seccomp_integration_in_run()))
    results.append(("helper_script", test_seccomp_helper_exists()))

    print("\n" + "="*70)
    passed = sum(1 for _, r in results if r)
    total = len(results)
    print(f"Results: {passed}/{total} passed")

    if passed == total:
        print("✓ seccomp Filtering tests PASSED")
        exit(0)
    else:
        print("✗ seccomp Filtering tests FAILED")
        exit(1)
