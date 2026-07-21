"""
tests/security/test_edge_cases.py — Tests for Phase 5 edge case hardening (E1-E7)
"""
import unittest
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


class TestPreflight(unittest.TestCase):
    """E1: Pre-flight binary checks."""

    def test_check_binaries_with_existing(self):
        from lib.preflight import check_binaries
        # 'sh' exists on every Linux system
        check_binaries(["sh"])

    def test_check_binaries_missing_exits(self):
        from lib.preflight import check_binaries
        with self.assertRaises(SystemExit):
            check_binaries(["nonexistent_binary_xyz_123"])

    def test_check_container_deps_callable(self):
        from lib.preflight import check_container_deps
        # Just verify it's importable and callable
        self.assertTrue(callable(check_container_deps))


class TestLocking(unittest.TestCase):
    """E2: Concurrent instance protection."""

    def test_acquire_and_release(self):
        from lib.lock import acquire_lock, release_lock
        acquire_lock("test_unit")
        release_lock("test_unit")

    def test_double_acquire_fails(self):
        from lib.lock import acquire_lock, release_lock
        acquire_lock("test_double")
        # Second acquire on same name from same process — flock is per-fd, so we
        # need to simulate via a subprocess
        import subprocess
        result = subprocess.run(
            [sys.executable, "-c",
             "from lib.lock import acquire_lock; acquire_lock('test_double')"],
            capture_output=True, text=True, timeout=5,
            cwd=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        )
        self.assertNotEqual(result.returncode, 0)
        release_lock("test_double")


class TestCorruptedToml(unittest.TestCase):
    """E4: Corrupted meta.toml handling."""

    def test_safe_toml_load_valid(self):
        import tempfile
        from common.sanitize import safe_toml_load
        with tempfile.NamedTemporaryFile(suffix=".toml", mode="w", delete=False) as f:
            f.write('key = "value"\n')
            path = f.name
        try:
            result = safe_toml_load(path)
            self.assertEqual(result["key"], "value")
        finally:
            os.remove(path)

    def test_safe_toml_load_corrupted(self):
        import tempfile
        from common.sanitize import safe_toml_load
        with tempfile.NamedTemporaryFile(suffix=".toml", mode="w", delete=False) as f:
            f.write("this is not valid toml {{{{")
            path = f.name
        try:
            result = safe_toml_load(path)
            self.assertEqual(result, {})
        finally:
            os.remove(path)

    def test_safe_toml_load_missing(self):
        from common.sanitize import safe_toml_load
        result = safe_toml_load("/nonexistent/path/meta.toml")
        self.assertEqual(result, {})


class TestNSTypeSafety(unittest.TestCase):
    """E5: NS class rejects typos."""

    def test_declared_attr_returns_none(self):
        from cli.parser import NS
        ns = NS()
        ns.name = "test"
        ns.value = None
        self.assertIsNone(ns.value)

    def test_undeclared_attr_raises(self):
        from cli.parser import NS
        ns = NS()
        ns.name = "test"
        with self.assertRaises(AttributeError):
            _ = ns.naem  # typo


class TestBtrfsCheck(unittest.TestCase):
    """E6: Btrfs filesystem detection."""

    def test_check_btrfs_on_tmp(self):
        from common.sanitize import check_btrfs
        # /tmp is usually tmpfs, not btrfs — should error
        with self.assertRaises(SystemExit):
            check_btrfs("/tmp")


class TestVethHashing(unittest.TestCase):
    """E7: Hash-based veth naming avoids collisions."""

    def test_different_names_different_hashes(self):
        import hashlib
        name1 = "container-alpha-20260101"
        name2 = "container-alpha-20260102"
        h1 = f"sd-{hashlib.sha1(name1.encode()).hexdigest()[:8]}"
        h2 = f"sd-{hashlib.sha1(name2.encode()).hexdigest()[:8]}"
        self.assertNotEqual(h1, h2)

    def test_veth_name_under_15_chars(self):
        import hashlib
        name = "very-long-container-name-that-would-overflow"
        h = f"sd-{hashlib.sha1(name.encode()).hexdigest()[:8]}"
        self.assertLessEqual(len(h), 15)


class TestCleanupStack(unittest.TestCase):
    """R1: Signal-safe cleanup stack."""

    def test_register_and_run(self):
        from lib.cleanup import register_cleanup, _run_cleanup, _cleanup_stack
        called = []
        register_cleanup(lambda: called.append(1))
        register_cleanup(lambda: called.append(2))
        _run_cleanup()
        # LIFO order
        self.assertEqual(called, [2, 1])

    def test_unregister(self):
        from lib.cleanup import register_cleanup, unregister_cleanup, _cleanup_stack
        fn = lambda: None
        register_cleanup(fn)
        unregister_cleanup(fn)
        self.assertNotIn((fn, ()), _cleanup_stack)


class TestValidModes(unittest.TestCase):
    """B1: VALID_MODES includes json."""

    def test_json_in_valid_modes(self):
        from lib.variables.general import VALID_MODES
        self.assertIn("json", VALID_MODES)


class TestPrivilegeArgValidation(unittest.TestCase):
    """B5: Privilege fallback argument validation (only when helper absent)."""

    def _helper_missing(self):
        from lib.privilege import HELPER_GENERAL, _has_helper
        return not _has_helper(HELPER_GENERAL)

    def test_chown_insufficient_args(self):
        if not self._helper_missing():
            self.skipTest("sd-priv helper installed, fallback path not used")
        from lib.privilege import _priv_general
        with self.assertRaises(ValueError):
            _priv_general("own:chown", "1000")

    def test_mkdir_no_args(self):
        if not self._helper_missing():
            self.skipTest("sd-priv helper installed, fallback path not used")
        from lib.privilege import _priv_general
        with self.assertRaises(ValueError):
            _priv_general("sys:mkdir")

    def test_unknown_operation(self):
        if not self._helper_missing():
            self.skipTest("sd-priv helper installed, fallback path not used")
        from lib.privilege import _priv_general
        with self.assertRaises(ValueError):
            _priv_general("fake:op", "arg")


if __name__ == "__main__":
    unittest.main()
