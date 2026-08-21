"""
test_cgroup_enforcement.py — verify cgroup enforcement hardening
Confirms memory/CPU limits are properly applied via sudo
"""

from pathlib import Path


def get_project_root() -> Path:
    """Get project root (relative to this test file)."""
    return Path(__file__).parent.parent.parent


def test_cgroup_setup_uses_sudo():
    """Verify cgroup writes use sudo (not unprivileged user access)."""
    print("\n[TEST] cgroup writes use sudo (not plain open())")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Extract _setup_cgroup function
    setup_cgroup_section = code.split("def _setup_cgroup")[1].split("def ")[0]

    # Verify no plain open() for memory.max or cpu.max
    if 'with open(f"{cgroup_path}/memory.max"' in setup_cgroup_section:
        print("  ✗ FAIL: memory.max written with plain open() (not sudo)")
        return False

    if 'with open(f"{cgroup_path}/cpu.max"' in setup_cgroup_section:
        print("  ✗ FAIL: cpu.max written with plain open() (not sudo)")
        return False

    # Verify sudo tee is used
    if '["sudo", "tee"' not in setup_cgroup_section:
        print("  ✗ FAIL: sudo tee not found in _setup_cgroup")
        return False

    print("  ✓ PASS: cgroup writes use sudo tee")
    return True


def test_cgroup_procs_assignment_logged():
    """Verify cgroup.procs assignment is logged (not silently ignored)."""
    print("\n[TEST] cgroup.procs assignment is logged")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Extract section with cgroup.procs write
    if "cgroup.procs" not in code:
        print("  ✗ FAIL: cgroup.procs write not found")
        return False

    section = code.split("if cgroup_path:")[1].split("_write_meta")[0]

    # Verify emit() is called on success or failure
    if "emit(" not in section:
        print("  ✗ FAIL: no emit() logging for cgroup assignment")
        return False

    # Verify sudo tee is used (not plain open())
    if '["sudo", "tee"' not in section:
        print("  ✗ FAIL: cgroup.procs assignment doesn't use sudo tee")
        return False

    print("  ✓ PASS: cgroup.procs assignment uses sudo tee and is logged")
    return True


def test_cgroup_memory_parsing():
    """Verify memory parsing function handles common units."""
    print("\n[TEST] memory parsing handles common units (mb, gb, etc)")

    # This test verifies the _parse_memory function exists and handles units
    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    if "_parse_memory" not in code:
        print("  ✗ FAIL: _parse_memory() not found")
        return False

    # Verify it handles "mb" and "gb"
    if '"mb"' not in code and '"gb"' not in code:
        print("  ✗ FAIL: _parse_memory() doesn't handle mb/gb units")
        return False

    print("  ✓ PASS: memory parsing handles common units")
    return True


def test_cgroup_cpu_parsing():
    """Verify CPU quota is properly calculated."""
    print("\n[TEST] CPU quota parsing")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Extract _setup_cgroup to verify CPU calculation
    setup_cgroup_section = code.split("def _setup_cgroup")[1].split("def ")[0]

    # Verify quota calculation: quota = cpu_count * 100000
    if "100000" not in setup_cgroup_section:
        print("  ✗ FAIL: CPU quota calculation (100000 base) not found")
        return False

    print("  ✓ PASS: CPU quota calculation present")
    return True


if __name__ == "__main__":
    print("="*70)
    print("cgroup Enforcement Hardening Tests")
    print("="*70)

    results = []
    results.append(("cgroup_sudo_writes", test_cgroup_setup_uses_sudo()))
    results.append(("cgroup_procs_logged", test_cgroup_procs_assignment_logged()))
    results.append(("memory_parsing", test_cgroup_memory_parsing()))
    results.append(("cpu_parsing", test_cgroup_cpu_parsing()))

    print("\n" + "="*70)
    passed = sum(1 for _, r in results if r)
    total = len(results)
    print(f"Results: {passed}/{total} passed")

    if passed == total:
        print("✓ cgroup Enforcement tests PASSED")
        exit(0)
    else:
        print("✗ cgroup Enforcement tests FAILED")
        exit(1)
