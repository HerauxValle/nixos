"""
tests/cmd.py — sd penetrate command
Only active when tests/script.sh exists.
"""

import os
import subprocess
import sys

SCRIPT = os.path.join(os.path.dirname(__file__), "script.sh")

SUITES = {"all", "imports", "cli", "image", "rules", "modes", "cleanup"}


def penetrate(suite: str = "all") -> None:
    from common.errors import error

    if not os.path.isfile(SCRIPT):
        error("PENETRATE_MISSING", "tests/script.sh not found")

    if suite not in SUITES:
        error("UNKNOWN_SUITE", f"unknown suite '{suite}'",
              f"valid: {', '.join(sorted(SUITES))}")

    subprocess.run(["bash", SCRIPT, suite])