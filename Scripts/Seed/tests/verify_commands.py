#!/usr/bin/env python3
"""
tests/verify_commands.py — Automated command verification
Dynamically discovers all commands from cli/commands.py and tests them.
Usage: python3 tests/verify_commands.py [--img PATH]
"""

import subprocess, sys, os, json, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

# ── config ──────────────────────────────────────────────────────────────────

DEFAULT_IMG = os.path.expanduser("~/Applications/SimpleDocker/test.img")


def run(args: list[str], timeout=120) -> tuple[int, str, str]:
    r = subprocess.run(
        [sys.executable, "main.py"] + args,
        capture_output=True, text=True, timeout=timeout, cwd=ROOT
    )
    return r.returncode, r.stdout, r.stderr


def extract_error(stdout: str, stderr: str) -> str:
    raw = stderr or stdout
    try:
        d = json.loads(raw)
        if isinstance(d, list):
            d = d[0]
        row = d.get("rows", [{}])[0]
        return f"{row.get('code', '?')}: {row.get('message', '?')}"
    except Exception:
        # strip ANSI
        import re
        clean = re.sub(r'\x1b\[[0-9;]*m', '', raw)
        return clean.strip()[:120] or "(no output)"


# ── test definitions ────────────────────────────────────────────────────────
# Each test: (label, args, requires_img, cleanup_args)
# Tests run in order. Some have dependencies (e.g. add before delete).

def build_tests(img_path: str) -> list[tuple[str, list[str], bool, list]]:
    return [
        # ── help & utilities ──
        ("help",                    ["help"],                                           False, []),

        # ── image ──
        ("image select",            ["-j", "image", "select", img_path],                False, []),
        ("image which",             ["-j", "image", "which"],                           True,  []),
        ("image list",              ["-j", "image", "list"],                            False, []),

        # ── utilities (need active session) ──
        ("layers",                  ["-j", "layers"],                                    True,  []),
        ("processes",               ["-j", "processes"],                                 True,  []),
        ("rules",                   ["-j", "rules"],                                     True,  []),

        # ── blueprint ──
        ("blueprint list",          ["-j", "blueprint", "list"],                        True,  []),
        ("blueprint validate -all", ["-j", "blueprint", "validate", "-all"],            True,  []),

        # ── format ──
        ("format list",             ["-j", "format", "list"],                           True,  []),

        # ── container ──
        ("container list",          ["-j", "container", "list"],                        True,  []),

        # ── profile ──
        ("profile list",            ["-j", "profile", "list"],                          True,  []),

        # ── config ──
        ("config list",             ["-j", "config", "list"],                           True,  []),
        ("config set",              ["-j", "config", "set", "rule", "encryption_default_preset", "strong"], True, []),
        ("config unset",            ["-j", "config", "unset", "rule", "encryption_default_preset"],         True, []),
        ("config reset",            ["-j", "config", "reset"],                          True,  []),
        ("config edit",             ["-j", "config", "edit", "rules"],                  True,  []),
        ("config edit",             ["-j", "config", "edit", "rules"],                  True,  []),

        # ── encryption: list ──
        ("encryption list slots",   ["-j", "encryption", "list", "slots"],             True,  []),
        ("encryption list all",     ["-j", "encryption", "list", "all"],               True,  []),
        ("encryption list verified",["-j", "encryption", "list", "verified"],          True,  []),

        # ── encryption: add/rename/delete keys ──
        ("encryption add key",      ["-j", "encryption", "add", "key", "test_pw_1"],           True,  []),
        ("encryption add key -n",   ["-j", "encryption", "add", "key", "test_pw_2", "-n", "vk_named"], True, []),
        ("encryption rename",       ["-j", "encryption", "rename", "7", "vk_renamed"],        True,  []),
        ("encryption delete key",   ["-j", "encryption", "delete", "key", "vk_named"],       True,  []),
        ("encryption delete key 2", ["-j", "encryption", "delete", "key", "vk_renamed"],     True,  []),

        # ── encryption: verify/unverify ──
        ("encryption verify",       ["-j", "encryption", "verify", "-n", "vk_host"],   True,  []),
        ("encryption unverify",     ["-j", "encryption", "unverify", "vk_host"],       True,  []),

        # ── encryption: presets ──
        ("encryption create preset",["-j", "encryption", "create", "preset", "vk_pr",
                                     "-argon2-memory", "33554432", "-argon2-time", "4",
                                     "-argon2-parallel", "1"],                          True,  []),
        ("encryption delete preset",["-j", "encryption", "delete", "preset", "vk_pr"],       True,  []),

        # ── encryption: enable/disable/refresh ──
        ("encryption add (enable)", ["-j", "encryption", "add", "key", "enable_pw"],         True,  []),
        ("encryption enable",       ["-j", "encryption", "enable"],                    True,  []),
        ("encryption disable",      ["-j", "encryption", "disable"],                   True,  []),
        ("encryption delete (cleanup)",["-j", "encryption", "delete", "key", "7"],     True,  []),
        ("encryption refresh auth", ["-j", "encryption", "refresh", "auth"],           True,  []),

        # ── close & restore ──
        ("image close",             ["-j", "image", "close"],                           True,  []),
        ("image select (restore)",  ["-j", "image", "select", img_path],                False, []),
        ("image close -all",        ["-j", "image", "close", "-all"],                   True,  []),
    ]


# ── runner ──────────────────────────────────────────────────────────────────

def main():
    img = DEFAULT_IMG
    if "--img" in sys.argv:
        idx = sys.argv.index("--img")
        img = sys.argv[idx + 1]

    if not os.path.isfile(img):
        print(f"ERROR: img not found: {img}")
        print(f"Create one first: python3 main.py create image {os.path.dirname(img)}/ -n test")
        sys.exit(1)

    tests = build_tests(img)
    results = []
    failures = []
    t0 = time.time()

    for label, args, needs_img, cleanup in tests:
        rc, stdout, stderr = run(args)
        passed = rc == 0
        results.append((label, passed))
        if passed:
            print(f"  \033[32mPASS\033[0m | {label}")
        else:
            err = extract_error(stdout, stderr)
            print(f"  \033[91mFAIL\033[0m | {label}")
            failures.append((label, args, err))

        # Run cleanup if any
        for c in cleanup:
            run(c)

    elapsed = time.time() - t0
    passed = sum(1 for _, p in results if p)
    total = len(results)

    print(f"\n{'=' * 60}")
    print(f"  {passed}/{total} passed in {elapsed:.1f}s")
    print(f"{'=' * 60}")

    if failures:
        print(f"\n  \033[91mFailed commands:\033[0m\n")
        for label, args, err in failures:
            print(f"  {label}")
            print(f"    cmd:   sd {' '.join(args)}")
            print(f"    error: {err}")
            print()

    sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
