#!/usr/bin/env python3
"""
tests/security/test_sanitize.py — Input validation security tests.
Verifies that safe_name, safe_pid, safe_path_within reject malicious input.
"""

import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)


class TestSafeName(unittest.TestCase):
    """Verify safe_name rejects path traversal, null bytes, separators."""

    def _call(self, name, label="test"):
        from common.sanitize import safe_name
        return safe_name(name, label)

    def test_valid_name(self):
        self.assertEqual(self._call("my-container"), "my-container")

    def test_valid_name_with_dots(self):
        self.assertEqual(self._call("v1.2.3"), "v1.2.3")

    def test_rejects_empty(self):
        with self.assertRaises(SystemExit):
            self._call("")

    def test_rejects_null_byte(self):
        with self.assertRaises(SystemExit):
            self._call("name\x00evil")

    def test_rejects_forward_slash(self):
        with self.assertRaises(SystemExit):
            self._call("../../etc/passwd")

    def test_rejects_backslash(self):
        with self.assertRaises(SystemExit):
            self._call("name\\evil")

    def test_rejects_dotdot(self):
        with self.assertRaises(SystemExit):
            self._call("..")

    def test_rejects_dotdot_in_name(self):
        with self.assertRaises(SystemExit):
            self._call("foo..bar")

    def test_rejects_long_name(self):
        with self.assertRaises(SystemExit):
            self._call("a" * 256)

    def test_max_length_ok(self):
        name = "a" * 255
        self.assertEqual(self._call(name), name)


class TestSafePid(unittest.TestCase):
    """Verify safe_pid rejects invalid PIDs."""

    def _call(self, pid, label="test"):
        from common.sanitize import safe_pid
        return safe_pid(pid, label)

    def test_rejects_zero(self):
        with self.assertRaises(SystemExit):
            self._call(0)

    def test_rejects_negative(self):
        with self.assertRaises(SystemExit):
            self._call(-1)

    def test_rejects_huge_pid(self):
        with self.assertRaises(SystemExit):
            self._call(99999999)

    def test_rejects_string(self):
        with self.assertRaises(SystemExit):
            self._call("not-a-pid")

    def test_rejects_shell_injection(self):
        with self.assertRaises(SystemExit):
            self._call("1; rm -rf /")

    def test_accepts_own_pid(self):
        """Current process PID should always be valid."""
        result = self._call(os.getpid())
        self.assertEqual(result, os.getpid())

    def test_accepts_pid_1(self):
        """PID 1 (init) should always exist."""
        result = self._call(1)
        self.assertEqual(result, 1)


class TestSafePathWithin(unittest.TestCase):
    """Verify safe_path_within prevents directory escape."""

    def _call(self, base, user_part, label="test"):
        from common.sanitize import safe_path_within
        return safe_path_within(base, user_part, label)

    def test_valid_path(self):
        result = self._call("/tmp", "subdir/file.txt")
        self.assertEqual(result, "/tmp/subdir/file.txt")

    def test_rejects_dotdot_escape(self):
        with self.assertRaises(SystemExit):
            self._call("/tmp/sandbox", "../../etc/passwd")

    def test_rejects_absolute_override(self):
        with self.assertRaises(SystemExit):
            self._call("/tmp/sandbox", "/etc/passwd")

    def test_dotdot_within_base_ok(self):
        """Path that resolves back into base is allowed."""
        # /tmp/sandbox/a/../b → /tmp/sandbox/b (still within base)
        base = "/tmp"
        result = self._call(base, "a/../b")
        self.assertTrue(result.startswith(base))


if __name__ == "__main__":
    unittest.main()
