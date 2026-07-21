#!/usr/bin/env python3
"""
run_all.py — run all hardening tests
Executes all 5 phases of container isolation hardening verification
"""

import subprocess
import sys
from pathlib import Path


def run_test(test_name: str) -> tuple[int, str]:
    """Run a single test and return (returncode, output)."""
    test_path = Path(__file__).parent / f"test_{test_name}.py"
    result = subprocess.run(
        [sys.executable, str(test_path)],
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout + result.stderr


def main():
    tests = [
        "dev_isolation",
        "cgroup_enforcement",
        "mount_hardening",
        "capability_dropping",
        "seccomp_filtering",
    ]

    print("="*70)
    print("Running All Container Hardening Tests")
    print("="*70 + "\n")

    results = {}
    for test in tests:
        returncode, output = run_test(test)
        results[test] = returncode == 0

        # Extract summary line from output
        for line in output.split("\n"):
            if "✓" in line or "✗" in line:
                if "Results:" in line or "PASSED" in line or "FAILED" in line:
                    print(line)

    print("\n" + "="*70)
    passed = sum(1 for v in results.values() if v)
    total = len(results)
    print(f"Overall: {passed}/{total} test suites passed")

    if passed == total:
        print("✓ ALL TESTS PASSED")
        return 0
    else:
        failed = [k for k, v in results.items() if not v]
        print(f"✗ FAILED TESTS: {', '.join(failed)}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
