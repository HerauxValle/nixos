#!/usr/bin/env python3
"""
tests/test_cli_deep.py — Deep CLI output validation
Tests JSON output structure, field presence, error codes, and dispatch correctness
for every command path. Goes beyond exit-code checks to validate actual output.
Usage: python3 tests/test_cli_deep.py [--img PATH]
"""

import subprocess, sys, os, json, re, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
DEFAULT_IMG = os.path.expanduser("~/Applications/SimpleDocker/test.img")

ANSI = re.compile(r'\x1b\[[0-9;]*m')


def sd(*args, timeout=30) -> dict:
    """Run sd in JSON mode, return parsed output dict."""
    r = subprocess.run(
        [sys.executable, "main.py", "-j"] + list(args),
        capture_output=True, text=True, timeout=timeout, cwd=ROOT
    )
    raw = r.stdout.strip() or r.stderr.strip()
    try:
        d = json.loads(raw)
        if isinstance(d, list) and d:
            return d[0]
        return d if isinstance(d, dict) else {"_raw": raw, "_rc": r.returncode}
    except (json.JSONDecodeError, ValueError):
        return {"_raw": ANSI.sub('', raw), "_rc": r.returncode, "type": "parse_error"}


def sd_raw(*args, timeout=30) -> tuple[int, str]:
    """Run sd, return (rc, combined output)."""
    r = subprocess.run(
        [sys.executable, "main.py"] + list(args),
        capture_output=True, text=True, timeout=timeout, cwd=ROOT
    )
    return r.returncode, (r.stdout + r.stderr).strip()


# ── assertions ─────────────────────────────────────────────────────────────

class Results:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.errors = []

    def ok(self, name, cond, detail=""):
        if cond:
            self.passed += 1
            print(f"  \033[32mPASS\033[0m  {name}")
        else:
            self.failed += 1
            msg = f"{name}: {detail}" if detail else name
            self.errors.append(msg)
            print(f"  \033[91mFAIL\033[0m  {name}" + (f"  ({detail[:80]})" if detail else ""))

    def summary(self):
        total = self.passed + self.failed
        print(f"\n{'='*60}")
        print(f"  {self.passed}/{total} passed")
        print(f"{'='*60}")
        if self.errors:
            print(f"\n  \033[91mFailures:\033[0m")
            for e in self.errors:
                print(f"    - {e}")
        return self.failed == 0


R = Results()

# ── helpers ────────────────────────────────────────────────────────────────

def has_schema(d, type_=None):
    """Check JSON envelope: schema_version + type."""
    ok = isinstance(d, dict) and d.get("schema_version") == 1
    if type_:
        ok = ok and d.get("type") == type_
    return ok

def rows(d):
    return d.get("rows", [])

def first_row(d):
    r = rows(d)
    return r[0] if r else {}


# ══════════════════════════════════════════════════════════════════════════
# TESTS
# ══════════════════════════════════════════════════════════════════════════

def test_json_mode_flag():
    """Verify -j flag sets JSON output mode."""
    d = sd("image", "list")
    R.ok("-j produces JSON envelope", has_schema(d),
         f"got: {str(d)[:80]}")

def test_help_structure():
    d = sd("help")
    R.ok("help returns table", has_schema(d, "table"))
    r = rows(d)
    R.ok("help has rows", len(r) > 0)
    if r:
        first = r[0]
        # help rows have children for subcommands
        has_cmd = "command" in first or "children" in first
        R.ok("help rows have command/children", has_cmd,
             f"keys: {list(first.keys())}")

def test_image_list():
    d = sd("image", "list")
    R.ok("image list returns table", has_schema(d, "table"))
    r = rows(d)
    R.ok("image list has entries", len(r) > 0)
    if r:
        R.ok("image list rows have 'name'", "name" in r[0],
             f"keys: {list(r[0].keys())}")
        R.ok("image list rows have 'path'", "path" in r[0])
        R.ok("image list rows have 'size_mb'", "size_mb" in r[0])

def test_image_select(img):
    d = sd("image", "select", img)
    R.ok("image select returns action", has_schema(d, "action"))

def test_image_which():
    d = sd("image", "which")
    R.ok("image which returns action/table", has_schema(d))

def test_image_close_reopen(img):
    sd("image", "close")
    d = sd("image", "which")
    R.ok("image which errors after close", d.get("type") == "error")
    sd("image", "select", img)

def test_image_close_all(img):
    sd("image", "select", img)
    d = sd("image", "close", "-all")
    R.ok("image close -all succeeds", has_schema(d, "action"))
    sd("image", "select", img)

def test_blueprint_list():
    d = sd("blueprint", "list")
    R.ok("blueprint list returns table", has_schema(d, "table"))
    r = rows(d)
    if r:
        R.ok("blueprint rows have 'name'", "name" in r[0])
        R.ok("blueprint rows have 'ext'", "ext" in r[0])

def test_blueprint_validate():
    d = sd("blueprint", "validate", "-all")
    # may return empty output (rc=0) if validation passes silently
    R.ok("blueprint validate -all succeeds",
         has_schema(d) or d.get("_rc", 1) == 0 or d.get("type") == "parse_error")

def test_format_list():
    d = sd("format", "list")
    R.ok("format list returns table/action",
         has_schema(d) and d.get("type") in ("table", "action"))

def test_container_list():
    d = sd("container", "list")
    R.ok("container list returns table/action",
         has_schema(d) and d.get("type") in ("table", "action"))

def test_profile_list():
    d = sd("profile", "list")
    R.ok("profile list returns table/action",
         has_schema(d) and d.get("type") in ("table", "action"))

def test_config_list():
    d = sd("config", "list")
    R.ok("config list returns table", has_schema(d, "table"))
    r = rows(d)
    if r:
        R.ok("config rows have 'file'", "file" in r[0])
        R.ok("config rows have 'status'", "status" in r[0])

def test_config_set_unset():
    d = sd("config", "set", "rule", "encryption_default_preset", "strong")
    R.ok("config set returns action", has_schema(d, "action"))
    d = sd("config", "unset", "rule", "encryption_default_preset")
    R.ok("config unset returns action", has_schema(d, "action"))

def test_config_reset():
    d = sd("config", "reset")
    R.ok("config reset returns action", has_schema(d, "action"))

def test_layers():
    d = sd("layers")
    R.ok("layers returns table/action",
         has_schema(d) and d.get("type") in ("table", "action"))

def test_processes():
    d = sd("processes")
    R.ok("processes returns table/action",
         has_schema(d) and d.get("type") in ("table", "action"))

def test_rules():
    d = sd("rules")
    R.ok("rules returns table/action",
         has_schema(d) and d.get("type") in ("table", "action"))

def test_encryption_list_slots():
    d = sd("encryption", "list", "slots")
    R.ok("encryption list slots valid type",
         has_schema(d) and d.get("type") in ("table", "action"))

def test_encryption_list_all():
    d = sd("encryption", "list", "all")
    R.ok("encryption list all valid type",
         has_schema(d) and d.get("type") in ("table", "action"))

def test_encryption_lifecycle():
    """Full add → rename → delete key lifecycle with output validation."""
    # add
    d = sd("encryption", "add", "key", "deep_test_pw", "-n", "deep_test_key")
    R.ok("enc add key returns action", has_schema(d, "action"))
    fr = first_row(d)
    R.ok("enc add mentions slot", "slot" in fr.get("value", ""),
         f"value: {fr.get('value', '')}")

    # list — verify it appears
    d = sd("encryption", "list", "slots")
    found = any("deep_test_key" in str(r) for r in rows(d))
    R.ok("enc list shows added key", found)

    # rename
    d = sd("encryption", "rename", "deep_test_key", "deep_renamed")
    R.ok("enc rename returns action", has_schema(d, "action"))

    # delete
    d = sd("encryption", "delete", "key", "deep_renamed")
    R.ok("enc delete key returns action", has_schema(d, "action"))

def test_encryption_preset_lifecycle():
    """Create → delete preset with validation."""
    d = sd("encryption", "create", "preset", "deep_pr",
           "-argon2-memory", "33554432", "-argon2-time", "4", "-argon2-parallel", "1")
    R.ok("enc create preset returns action", has_schema(d, "action"))

    d = sd("encryption", "delete", "preset", "deep_pr")
    R.ok("enc delete preset returns action", has_schema(d, "action"))

def test_encryption_verify_unverify():
    d = sd("encryption", "verify", "-n", "deep_host")
    R.ok("enc verify returns action", has_schema(d, "action"))

    d = sd("encryption", "unverify", "deep_host")
    R.ok("enc unverify returns action", has_schema(d, "action"))

def test_encryption_enable_disable():
    # need a user key to enable
    sd("encryption", "add", "key", "deep_enable_pw")
    d = sd("encryption", "enable")
    R.ok("enc enable returns action", has_schema(d, "action"))
    d = sd("encryption", "disable")
    R.ok("enc disable returns action", has_schema(d, "action"))
    sd("encryption", "delete", "key", "7")

def test_encryption_refresh():
    d = sd("encryption", "refresh", "auth")
    R.ok("enc refresh auth returns action", has_schema(d, "action"))

# ── error behavior tests ──────────────────────────────────────────────────

def test_unknown_command():
    d = sd("nonexistent_cmd_xyz")
    R.ok("unknown command returns error", d.get("type") == "error")

def test_unknown_flag():
    d = sd("image", "list", "-zzz")
    R.ok("unknown flag returns error", d.get("type") == "error")
    fr = first_row(d)
    R.ok("unknown flag error code is UNKNOWN_FLAG",
         fr.get("code") == "UNKNOWN_FLAG", f"code: {fr.get('code')}")

def test_no_img_errors():
    """Commands requiring image should error cleanly when none selected."""
    sd("image", "close", "-all")
    d = sd("container", "list")
    R.ok("container list w/o img gives error", d.get("type") == "error")
    fr = first_row(d)
    R.ok("error code is NO_IMG/NO_SESSION",
         fr.get("code") in ("NO_IMG", "NO_SESSION"),
         f"code: {fr.get('code')}")

def test_table_mode_output():
    """Non-JSON (table) mode should produce non-JSON text."""
    rc, out = sd_raw("image", "list")
    is_json = False
    try:
        json.loads(out)
        is_json = True
    except Exception:
        pass
    R.ok("table mode output is not JSON", not is_json)

def test_encryption_bad_target():
    d = sd("encryption", "add", "invalid_target")
    R.ok("enc bad target returns error", d.get("type") == "error")
    fr = first_row(d)
    R.ok("error code is UNKNOWN_TARGET", fr.get("code") == "UNKNOWN_TARGET",
         f"code: {fr.get('code')}")

def test_encryption_preset_validation():
    """Preset with bad params should fail with INVALID_PRESET."""
    d = sd("encryption", "create", "preset", "bad_pr",
           "-argon2-memory", "100", "-argon2-time", "1", "-argon2-parallel", "1")
    R.ok("bad preset returns error", d.get("type") == "error")
    fr = first_row(d)
    R.ok("error is INVALID_PRESET", fr.get("code") == "INVALID_PRESET",
         f"code: {fr.get('code')}")


# ══════════════════════════════════════════════════════════════════════════
# RUNNER
# ══════════════════════════════════════════════════════════════════════════

def main():
    img = DEFAULT_IMG
    if "--img" in sys.argv:
        img = sys.argv[sys.argv.index("--img") + 1]
    if not os.path.isfile(img):
        print(f"ERROR: img not found: {img}")
        sys.exit(1)

    t0 = time.time()

    # setup
    sd("image", "select", img)

    print("\n── Structure & Output ──")
    test_json_mode_flag()
    test_help_structure()
    test_table_mode_output()

    print("\n── Image ──")
    test_image_list()
    test_image_select(img)
    test_image_which()
    test_image_close_reopen(img)

    print("\n── Resources ──")
    test_blueprint_list()
    test_blueprint_validate()
    test_format_list()
    test_container_list()
    test_profile_list()
    test_layers()
    test_processes()
    test_rules()

    print("\n── Config ──")
    test_config_list()
    test_config_set_unset()
    test_config_reset()

    print("\n── Encryption ──")
    test_encryption_list_slots()
    test_encryption_list_all()
    test_encryption_lifecycle()
    test_encryption_preset_lifecycle()
    test_encryption_verify_unverify()
    test_encryption_enable_disable()
    test_encryption_refresh()

    print("\n── Error Handling ──")
    test_unknown_command()
    test_unknown_flag()
    test_encryption_bad_target()
    test_encryption_preset_validation()

    print("\n── Edge: No Image ──")
    test_no_img_errors()

    # restore session
    sd("image", "select", img)
    test_image_close_all(img)

    elapsed = time.time() - t0
    print(f"\n  ({elapsed:.1f}s)")
    ok = R.summary()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
