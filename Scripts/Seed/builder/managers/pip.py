"""
core/builder/managers/pip.py — Python pip package manager

Usage in [deps]:
  pip: requests flask pandas
  pip: torch torchvision --index-url=https://download.pytorch.org/whl/cpu
  pip: mypy types-requests --dev
"""

from builder.base import Manager


class PipManager(Manager):
    name = "pip"
    help_text = "pip: package1 package2 [--index-url=URL] [--dev]"

    def parse(self, args: str) -> dict:
        """
        Parse pip syntax: 'package1 package2 --index-url=URL --dev'

        Returns:
          {
            "packages": ["package1", "package2"],
            "index_url": "https://...",
            "dev": bool
          }
        """
        tokens = args.split()
        packages = []
        options = {}

        for token in tokens:
            if token.startswith("--"):
                # Parse --key=value or --flag
                if "=" in token:
                    key, val = token.split("=", 1)
                    options[key.lstrip("-")] = val
                else:
                    options[token.lstrip("-")] = True
            else:
                packages.append(token)

        if not packages:
            raise ValueError("pip: requires at least one package name")

        return {
            "packages": packages,
            "index_url": options.get("index-url"),
            "dev": options.get("dev", False),
        }

    def install(self, rootfs: str, parsed: dict) -> list[str]:
        """Generate pip install commands."""
        packages = " ".join(parsed["packages"])
        index_url = parsed.get("index_url")
        dev = parsed.get("dev", False)

        cmd = "pip install"
        if index_url:
            cmd += f" --index-url {index_url}"
        if dev:
            cmd += " --dev"
        cmd += f" {packages}"

        return [cmd]