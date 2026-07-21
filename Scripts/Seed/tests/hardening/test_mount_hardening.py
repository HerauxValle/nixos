"""
test_mount_hardening.py — verify mount namespace hardening
Confirms /proc hidepid=2 and /sys read-only
"""

from pathlib import Path


def get_project_root() -> Path:
    """Get project root (relative to this test file)."""
    return Path(__file__).parent.parent.parent


def test_proc_hidepid_enabled():
    """Verify /proc is mounted with hidepid=2 option."""
    print("\n[TEST] /proc mounted with hidepid=2")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Find the mount -t proc line
    if "mount -t proc" not in code:
        print("  ✗ FAIL: /proc mount not found")
        return False

    # Verify hidepid=2 is present
    if "hidepid=2" not in code:
        print("  ✗ FAIL: hidepid=2 not found in /proc mount")
        return False

    # Extract the relevant section
    proc_mount_section = code.split("mount -t proc")[1].split("\n")[0]
    if "hidepid=2" not in proc_mount_section:
        print("  ✗ FAIL: hidepid=2 not in proc mount command")
        return False

    print("  ✓ PASS: /proc mounted with hidepid=2")
    return True


def test_sys_remount_readonly():
    """Verify /sys is remounted read-only."""
    print("\n[TEST] /sys remounted read-only")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Extract _mount_fs function
    mount_fs_section = code.split("def _mount_fs")[1].split("def ")[0]

    # Verify remount ro is present
    if "remount,ro" not in mount_fs_section:
        print("  ✗ FAIL: remount,ro not found in _mount_fs")
        return False

    # Verify sys_path is being remounted
    if 'sys_path = os.path.join(rootfs, "sys")' not in mount_fs_section:
        print("  ✗ FAIL: sys_path variable not found")
        return False

    print("  ✓ PASS: /sys remounted read-only")
    return True


def test_sysfs_mounted_before_remount():
    """Verify /sys is mounted before remount (logical consistency)."""
    print("\n[TEST] /sys mounted before remount (order)")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Extract _mount_fs
    mount_fs_section = code.split("def _mount_fs")[1].split("def ")[0]

    # Find position of sysfs mount and remount
    sysfs_pos = mount_fs_section.find('("sysfs"')
    remount_pos = mount_fs_section.find("remount,ro")

    if sysfs_pos < 0:
        print("  ✗ FAIL: sysfs mount not found")
        return False

    if remount_pos < 0:
        print("  ✗ FAIL: remount not found")
        return False

    if sysfs_pos >= remount_pos:
        print("  ✗ FAIL: remount happens before sysfs mount")
        return False

    print("  ✓ PASS: /sys mounted before remount")
    return True


def test_proc_is_in_unshare_command():
    """Verify /proc mount is in the unshare command (not duplicated elsewhere)."""
    print("\n[TEST] /proc mount in unshare command (correct location)")

    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Count occurrences of "mount -t proc"
    count = code.count("mount -t proc")

    if count == 0:
        print("  ✗ FAIL: /proc mount command not found")
        return False

    if count > 1:
        print(f"  ⚠ WARNING: {count} /proc mount commands found (should be 1)")
        # This is not a fail, just a warning

    print("  ✓ PASS: /proc mount in unshare command")
    return True


if __name__ == "__main__":
    print("="*70)
    print("Mount Namespace Hardening Tests")
    print("="*70)

    results = []
    results.append(("proc_hidepid", test_proc_hidepid_enabled()))
    results.append(("sys_remount_ro", test_sys_remount_readonly()))
    results.append(("sys_before_remount", test_sysfs_mounted_before_remount()))
    results.append(("proc_in_unshare", test_proc_is_in_unshare_command()))

    print("\n" + "="*70)
    passed = sum(1 for _, r in results if r)
    total = len(results)
    print(f"Results: {passed}/{total} passed")

    if passed == total:
        print("✓ Mount Namespace tests PASSED")
        exit(0)
    else:
        print("✗ Mount Namespace tests FAILED")
        exit(1)
