"""
core/builder/managers/npm.py — Node.js npm package manager

Usage in [deps]:
  npm: react next express
  npm: eslint prettier --dev
  npm: lodash@4.17 moment@2.29
"""

from builder.base import Manager


class NpmManager(Manager):
    name = "npm"
    help_text = "npm: package1 package2 [--dev]"

    def parse(self, args: str) -> dict:
        """
        Parse npm syntax: 'package1 package2 --dev'

        Supports version specs: lodash@4.17, moment@latest

        Returns:
          {
            "packages": ["package1", "package2@version"],
            "dev": bool
          }
        """
        tokens = args.split()
        packages = []
        options = {}

        for token in tokens:
            if token.startswith("--"):
                key = token.lstrip("-")
                options[key] = True
            else:
                packages.append(token)

        if not packages:
            raise ValueError("npm: requires at least one package name")

        return {
            "packages": packages,
            "dev": options.get("dev", False),
        }

    def install(self, rootfs: str, parsed: dict) -> list[str]:
        """Generate npm install commands."""
        packages = " ".join(parsed["packages"])
        dev = parsed.get("dev", False)

        cmd = "npm install"
        if dev:
            cmd += " --save-dev"
        cmd += f" {packages}"

        return [cmd]