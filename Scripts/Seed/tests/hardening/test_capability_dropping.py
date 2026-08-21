"""
test_capability_dropping.py — verify capability dropping hardening
Confirms essential capabilities only, blocks dangerous ones
"""

from pathlib import Path


def get_project_root() -> Path:
    """Get project root (relative to this test file)."""
    return Path(__file__).parent.parent.parent


def test_capsh_in_init_script():
    """Verify capsh --drop is present in generated init script."""
    print("\n[TEST] capsh capability dropping in init script")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Extract _write_init_script function
    write_init_section = code.split("def _write_init_script")[1].split("def ")[0]

    # Verify capsh --drop is used
    if 'capsh --drop=all' not in write_init_section:
        print("  ✗ FAIL: capsh --drop=all not found in init script")
        return False

    # Verify capabilities are being kept (whitelist approach)
    if '--keep=' not in write_init_section:
        print("  ✗ FAIL: --keep= (capability whitelist) not found")
        return False

    print("  ✓ PASS: capsh --drop with --keep whitelist present")
    return True


def test_dangerous_caps_not_kept():
    """Verify dangerous capabilities (sys_admin, sys_ptrace, etc) are NOT kept."""
    print("\n[TEST] dangerous capabilities not in whitelist")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Extract the --keep section
    write_init_section = code.split("def _write_init_script")[1].split("def ")[0]
    keep_section = write_init_section.split("--keep=")[1].split("\n")[0]

    # Dangerous caps that should NOT be present
    dangerous = [
        "cap_sys_admin",     # unshare, mount, etc
        "cap_sys_ptrace",    # ptrace access
        "cap_bpf",           # eBPF programming
        "cap_perfmon",       # performance monitoring
        "cap_sys_module",    # load kernel modules
    ]

    for cap in dangerous:
        if cap in keep_section:
            print(f"  ✗ FAIL: dangerous capability {cap} found in whitelist")
            return False

    print("  ✓ PASS: dangerous capabilities not in whitelist")
    return True


def test_safe_caps_kept():
    """Verify essential capabilities are kept (chown, dac_override, net_bind_service)."""
    print("\n[TEST] essential capabilities kept")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Extract the --keep section
    write_init_section = code.split("def _write_init_script")[1].split("def ")[0]
    keep_section = write_init_section.split("--keep=")[1].split("\n")[0]

    # Essential caps that SHOULD be present
    essential = [
        "cap_chown",          # chown operations
        "cap_dac_override",   # file access (DAC bypass for root)
        "cap_setfcap",        # set capabilities on files
        "cap_net_bind_service",  # bind to low ports
    ]

    for cap in essential:
        if cap not in keep_section:
            print(f"  ✗ FAIL: essential capability {cap} not found in whitelist")
            return False

    print("  ✓ PASS: essential capabilities kept")
    return True


def test_capsh_fallback():
    """Verify fallback if capsh is not available (script still runs)."""
    print("\n[TEST] capsh fallback if not available")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Extract _write_init_script
    write_init_section = code.split("def _write_init_script")[1].split("def ")[0]

    # Verify fallback logic
    if "if command -v capsh" not in write_init_section:
        print("  ✗ FAIL: capsh existence check not found")
        return False

    if "else" not in write_init_section:
        print("  ✗ FAIL: else clause (fallback) not found")
        return False

    if "fi" not in write_init_section:
        print("  ✗ FAIL: fi (end if) not found")
        return False

    print("  ✓ PASS: capsh fallback logic present")
    return True


if __name__ == "__main__":
    print("="*70)
    print("Capability Dropping Hardening Tests")
    print("="*70)

    results = []
    results.append(("capsh_in_script", test_capsh_in_init_script()))
    results.append(("no_dangerous_caps", test_dangerous_caps_not_kept()))
    results.append(("keep_essential_caps", test_safe_caps_kept()))
    results.append(("capsh_fallback", test_capsh_fallback()))

    print("\n" + "="*70)
    passed = sum(1 for _, r in results if r)
    total = len(results)
    print(f"Results: {passed}/{total} passed")

    if passed == total:
        print("✓ Capability Dropping tests PASSED")
        exit(0)
    else:
        print("✗ Capability Dropping tests FAILED")
        exit(1)
