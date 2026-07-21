#!/usr/bin/env python3
"""
tests/security/test_path_traversal.py — Path traversal prevention tests.
Verifies that mount_profile, _mask_paths, and similar functions
cannot be tricked into operating outside their intended directories.
"""

import os
import sys
import unittest
import inspect

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)


class TestMountProfilePathTraversal(unittest.TestCase):
    """Verify mount_profile uses safe_path_within."""

    def test_source_uses_safe_path_within(self):
        """mount_profile must use safe_path_within for dst construction."""
        path = os.path.join(ROOT, "orchestration", "profile", "create.py")
        with open(path) as f:
            source = f.read()

        # Find mount_profile function
        self.assertIn("safe_path_within", source,
            "create.py must import/use safe_path_within")

        # Check it's used in mount_profile specifically
        in_func = False
        found = False
        for line in source.splitlines():
            if "def mount_profile" in line:
                in_func = True
            elif in_func:
                if line.strip() and not line[0].isspace():
                    break
                if "safe_path_within(" in line:
                    found = True
                    break

        self.assertTrue(found,
            "mount_profile must call safe_path_within for dst")

    def test_unmount_uses_safe_path_within(self):
        """unmount_profile must also use safe_path_within."""
        path = os.path.join(ROOT, "orchestration", "profile", "create.py")
        with open(path) as f:
            source = f.read()

        in_func = False
        found = False
        for line in source.splitlines():
            if "def unmount_profile" in line:
                in_func = True
            elif in_func:
                if line.strip() and not line[0].isspace():
                    break
                if "safe_path_within(" in line:
                    found = True
                    break

        self.assertTrue(found,
            "unmount_profile must call safe_path_within")


class TestMaskPathsTraversal(unittest.TestCase):
    """Verify _mask_paths in run.py uses safe_path_within."""

    def test_mask_paths_uses_safe_path_within(self):
        path = os.path.join(ROOT, "engine", "container", "run.py")
        with open(path) as f:
            source = f.read()

        in_func = False
        found = False
        for line in source.splitlines():
            if "def _mask_paths" in line:
                in_func = True
            elif in_func:
                if line.strip() and not line[0].isspace():
                    break
                if "safe_path_within(" in line:
                    found = True
                    break

        self.assertTrue(found,
            "_mask_paths must use safe_path_within")


class TestNoRawLstripSlash(unittest.TestCase):
    """Verify no unprotected lstrip('/') + os.path.join patterns remain."""

    CHECKED_FILES = [
        "orchestration/profile/create.py",
        "engine/container/run.py",
    ]

    def test_no_unprotected_lstrip(self):
        """lstrip('/') must always be wrapped by safe_path_within."""
        for relpath in self.CHECKED_FILES:
            fpath = os.path.join(ROOT, relpath)
            with open(fpath) as f:
                lines = f.readlines()

            for i, line in enumerate(lines, 1):
                if 'lstrip("/"' in line or "lstrip('/')" in line:
                    # This line uses lstrip — check that safe_path_within
                    # is used nearby (within 3 lines before or same line)
                    context = "".join(lines[max(0, i-4):i])
                    self.assertIn("safe_path_within", context,
                        f"{relpath}:{i} uses lstrip('/') without "
                        f"safe_path_within protection")


class TestLuksEmptyPassphrase(unittest.TestCase):
    """Verify LUKS operations reject empty passphrases."""

    def test_open_rejects_empty(self):
        """auto_open passkey path must reject empty passphrase."""
        path = os.path.join(ROOT, "lib", "encryption", "luks.py")
        with open(path) as f:
            source = f.read()
        self.assertIn("not passphrase.strip()", source,
            "luks.py must check for empty/whitespace-only passphrase")

    def test_add_key_rejects_empty(self):
        """add_key must reject empty new_passphrase."""
        path = os.path.join(ROOT, "lib", "encryption", "luks.py")
        with open(path) as f:
            source = f.read()
        self.assertIn("EMPTY_PASSPHRASE", source,
            "luks.py add_key must have EMPTY_PASSPHRASE error")


if __name__ == "__main__":
    unittest.main()
