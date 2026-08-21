"""
common/shebang.py — shebang scanning and resolution
Finds #! markers in files regardless of comment prefix (works for .ini, .jsonc, .py, etc.)
"""

import os
import re


def read_shebangs(path: str) -> list[str]:
    """
    Read all shebang values from the top of a file.
    Checks each line for #! anywhere in it (not just start).
    Stops at first line containing no #!
    Returns list of shebang values e.g. ["ruleset", "defaults"]
    """
    shebangs = []
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                stripped = line.strip()
                m = re.search(r"#!(\S+)", stripped)
                if m:
                    shebangs.append(m.group(1).strip())
                else:
                    break
    except Exception:
        pass
    return shebangs


def scan_dir(directory: str) -> dict[str, str]:
    """
    Recursively scan a directory for files by shebang.
    Returns {shebang_value: filepath} — first match per shebang wins.
    """
    result = {}
    if not os.path.isdir(directory):
        return result
    for root, _, files in os.walk(directory):
        for f in sorted(files):
            path     = os.path.join(root, f)
            shebangs = read_shebangs(path)
            for sb in shebangs:
                if sb not in result:
                    result[sb] = path
    return result


def find(shebang: str, *directories: str) -> str | None:
    """
    Find a file with a given shebang across multiple directories in order.
    Returns the first match or None.
    """
    for directory in directories:
        found = scan_dir(directory)
        if shebang in found:
            return found[shebang]
    return None


def list_dir(directory: str, known: set[str] = None) -> list[dict]:
    """
    List all files in a directory with their shebangs and status.
    known = set of expected shebang values to check against.
    Returns list of dicts: {file, shebang, status}
    """
    results      = []
    seen         = set()
    known        = known or set()

    if not os.path.isdir(directory):
        for sb in sorted(known):
            results.append({"file": "-", "shebang": f"#{sb}", "status": "missing"})
        return results

    for root, _, files in os.walk(directory):
        for f in sorted(files):
            path     = os.path.join(root, f)
            rel      = os.path.relpath(path, directory)
            shebangs = read_shebangs(path)
            known_sb = [sb for sb in shebangs if sb in known]
            unknown_sb = [sb for sb in shebangs if sb not in known]

            if not shebangs:
                status = "no shebang"
            elif known_sb:
                status = "valid"
                seen.update(known_sb)
            else:
                status = "unknown"

            label = ", ".join(f"#{s}" for s in shebangs) if shebangs else "-"
            results.append({"file": rel, "shebang": label, "status": status})

    # show missing known shebangs
    for sb in sorted(known):
        if sb not in seen:
            results.append({"file": "-", "shebang": f"#{sb}", "status": "missing"})

    return results


# back-compat re-export — use common.io.strip.jsonc directly in new code
from common.io.strip import jsonc as strip_jsonc_comments