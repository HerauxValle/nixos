#!/usr/bin/env python3
"""
tests/compile_all.py — verify all Python files compile without syntax errors
Run: python3 tests/compile_all.py
"""

import py_compile
import sys
from pathlib import Path

def main():
    root = Path(__file__).parent.parent
    py_files = [
        f for f in root.glob("**/*.py")
        if ".pycache" not in str(f) and ".claude" not in str(f)
    ]

    errors = []
    for fpath in sorted(py_files):
        try:
            py_compile.compile(str(fpath), doraise=True)
        except py_compile.PyCompileError as e:
            errors.append({
                "file": str(fpath).replace(str(root) + "/", ""),
                "error": str(e).split('\n')[0]
            })

    # Output
    if errors:
        print(f"FAIL | {len(errors)} files with syntax errors\n")
        for err in errors:
            print(f"  ✗ {err['file']}")
            print(f"    {err['error']}\n")
        return 1
    else:
        print(f"PASS | All {len(py_files)} Python files compile successfully")
        return 0

if __name__ == "__main__":
    sys.exit(main())
