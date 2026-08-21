#!/usr/bin/env python3
"""
tests/verify/render_types.py — Verify output rendering with different modes
Tests that all commands render correctly with: -j (json), -n (verbose), -t (table), and default

Available modes:
  -j  → json (structured JSON output)
  -n  → verbose (human-readable with details)
  -t  → table (formatted table output, default)
  (no flag) → default mode

Usage:
  python3 tests/verify/render_types.py              # uses 'sd select latest'
  python3 tests/verify/render_types.py /path/to/img # selects specific image
"""

import subprocess, sys, os, json

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)

MODES = {
    "json": "-j",
    "verbose": "-n",
    "table": "-t",
    "default": None,
}


def run(args: list[str], timeout=60) -> tuple[int, str, str]:
    """Run sd command and return (returncode, stdout, stderr)."""
    r = subprocess.run(
        [sys.executable, "main.py"] + args,
        capture_output=True, text=True, timeout=timeout, cwd=ROOT
    )
    return r.returncode, r.stdout, r.stderr


def validate_json(output: str) -> bool:
    """Check if output is valid JSON."""
    try:
        json.loads(output)
        return True
    except (json.JSONDecodeError, ValueError):
        return False


def test_command(label: str, cmd_args: list[str]) -> dict:
    """Test a command against all modes. Return results."""
    results = {}

    for mode_name, mode_flag in MODES.items():
        args = ([mode_flag] if mode_flag else []) + cmd_args
        rc, stdout, stderr = run(args)

        if rc != 0:
            results[mode_name] = {
                "status": "FAIL",
                "error": (stderr or stdout).strip()[:100],
            }
        else:
            # Validate output format
            is_valid = True
            if mode_name == "json":
                is_valid = validate_json(stdout)

            results[mode_name] = {
                "status": "PASS" if is_valid else "FAIL",
                "length": len(stdout),
                "preview": stdout.strip()[:80],
            }

    return results


def setup_session(img_path=None):
    """Select an image. If img_path is None, uses 'sd select latest'."""
    if img_path:
        print(f"Selecting image: {img_path}...")
        rc, _, err = run(["image", "select", img_path])
        if rc != 0:
            print(f"ERROR: Failed to select image at {img_path}")
            print(f"Details: {err}")
            sys.exit(1)
    else:
        print("Selecting latest image...")
        rc, _, err = run(["image", "select", "latest"])
        if rc != 0:
            print(f"ERROR: Failed to select latest image")
            print(f"Details: {err}")
            sys.exit(1)

    print("✓ Session active\n")


def main():
    # Parse args
    img_path = None
    if len(sys.argv) > 1:
        img_path = sys.argv[1]

    # Setup session
    setup_session(img_path)

    # Test suite: (label, command_args, skip_modes)
    tests = [
        ("help", ["help"], set()),  # help now uses emit(), supports all modes
        ("image list", ["image", "list"], set()),
        ("image which", ["image", "which"], set()),
        ("blueprint list", ["blueprint", "list"], set()),
        ("format list", ["format", "list"], set()),
        ("container list", ["container", "list"], set()),
        ("config list", ["config", "list"], set()),
        ("profile list", ["profile", "list"], set()),
        ("layers", ["layers"], set()),
        ("processes", ["processes"], set()),
        ("rules", ["rules"], set()),
        ("encryption list slots", ["encryption", "list", "slots"], set()),
    ]

    print("=" * 80)
    print("Render Type Verification (All Modes)")
    print("=" * 80)
    print()

    all_passed = True
    total_tested = 0
    total_passed = 0

    for label, cmd_args, skip_modes in tests:
        print(f"Testing: {label}")
        results = test_command(label, cmd_args)

        for mode_name, result in results.items():
            if mode_name in skip_modes:
                print(f"  — {mode_name:10} (skipped)")
                continue

            total_tested += 1
            status = result["status"]
            status_char = "✓" if status == "PASS" else "✗"

            if status == "FAIL":
                all_passed = False
                print(f"  {status_char} {mode_name:10} — {result.get('error', 'invalid format')}")
            else:
                total_passed += 1
                print(f"  {status_char} {mode_name:10} — {result['length']} bytes")
        print()

    # Summary
    print("=" * 80)
    print(f"{total_passed}/{total_tested} render type combinations passed")
    print("=" * 80)

    if all_passed:
        print("✓ All commands render correctly in all modes")
        return 0
    else:
        print("✗ Some commands failed to render in certain modes")
        return 1


if __name__ == "__main__":
    sys.exit(main())
