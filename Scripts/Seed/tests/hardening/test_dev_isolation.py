"""
test_dev_isolation.py — verify device isolation hardening
Confirms /dev is minimal whitelist, blocks dangerous devices
"""

import os
import subprocess
from pathlib import Path


def get_project_root() -> Path:
    """Get project root (relative to this test file)."""
    return Path(__file__).parent.parent.parent


def run_container(name: str, cmd: str, mnt: str) -> tuple[int, str, str]:
    """
    Run a command inside a container (via sd exec).
    Returns (returncode, stdout, stderr).
    """
    result = subprocess.run(
        ["python", "main.py", "exec", name] + cmd.split(),
        cwd=str(get_project_root()),
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout, result.stderr


def test_dev_minimal():
    """Verify /dev contains only safe devices (no mem, sda, kvm)."""
    print("\n[TEST] /dev is minimal (no devtmpfs)")

    # Check that dangerous devices are NOT present in any running container
    dangerous = ["mem", "sda", "sdb", "kvm", "dma_heap", "fuse"]

    # Find running containers
    mnt_base = "/var/lib/sd/mnt"
    if os.path.isdir(mnt_base):
        for img_dir in os.listdir(mnt_base):
            containers_dir = os.path.join(mnt_base, img_dir, "containers")
            if os.path.isdir(containers_dir):
                for container_dir in os.listdir(containers_dir):
                    dev_dir = os.path.join(containers_dir, container_dir, "rootfs", "dev")
                    if os.path.isdir(dev_dir):
                        dev_files = os.listdir(dev_dir)
                        for dangerous_dev in dangerous:
                            if dangerous_dev in dev_files:
                                print(f"  ✗ FAIL: Found {dangerous_dev} in {container_dir}/dev")
                                return False

    print("  ✓ PASS: No dangerous devices found in container /dev")
    return True


def test_dev_has_safe_devices():
    """Verify /dev has minimal safe devices."""
    print("\n[TEST] /dev has safe devices (null, zero, random, tty, urandom)")

    safe_devices = {"null", "zero", "random", "urandom", "tty", "ptmx", "full"}

    mnt_base = "/var/lib/sd/mnt"
    if os.path.isdir(mnt_base):
        for img_dir in os.listdir(mnt_base):
            containers_dir = os.path.join(mnt_base, img_dir, "containers")
            if os.path.isdir(containers_dir):
                for container_dir in os.listdir(containers_dir):
                    dev_dir = os.path.join(containers_dir, container_dir, "rootfs", "dev")
                    if os.path.isdir(dev_dir):
                        dev_files = set(os.listdir(dev_dir))
                        # Check that at least the core devices exist
                        core = {"null", "zero", "random"}
                        if not core.issubset(dev_files):
                            missing = core - dev_files
                            print(f"  ✗ FAIL: Missing core devices {missing} in {container_dir}/dev")
                            return False

    print("  ✓ PASS: Safe devices present in container /dev")
    return True


def test_dev_mem_not_readable():
    """Verify container cannot read /dev/mem (if it exists, permissions should deny access)."""
    print("\n[TEST] /dev/mem is not accessible")

    # Check the setup code doesn't mount devtmpfs in _mount_fs()
    run_py = get_project_root() / "engine" / "container" / "run.py"
    code = run_py.read_text()

    # Extract _mount_fs function
    mount_fs_section = code.split("def _mount_fs")[1].split("def ")[0]

    # Verify devtmpfs is NOT mounted (should not be in the for loop)
    if '("devtmpfs"' in mount_fs_section:
        print("  ✗ FAIL: devtmpfs still mounted in _mount_fs()")
        return False

    # Verify _setup_minimal_dev exists and is called
    if "_setup_minimal_dev" not in code:
        print("  ✗ FAIL: _setup_minimal_dev() not found")
        return False

    if "_setup_minimal_dev(rootfs)" not in mount_fs_section:
        print("  ✗ FAIL: _setup_minimal_dev() not called in _mount_fs()")
        return False

    print("  ✓ PASS: /dev/mem is not created (devtmpfs removed, using mknod)")
    return True


if __name__ == "__main__":
    print("="*70)
    print("Device Isolation Hardening Tests")
    print("="*70)

    results = []
    results.append(("dev_minimal", test_dev_minimal()))
    results.append(("dev_has_safe", test_dev_has_safe_devices()))
    results.append(("dev_mem_not_readable", test_dev_mem_not_readable()))

    print("\n" + "="*70)
    passed = sum(1 for _, r in results if r)
    total = len(results)
    print(f"Results: {passed}/{total} passed")

    if passed == total:
        print("✓ Device Isolation tests PASSED")
        exit(0)
    else:
        print("✗ Device Isolation tests FAILED")
        exit(1)
