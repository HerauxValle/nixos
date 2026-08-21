"""
core/builder/managers/git.py — Git repository cloning

Usage in [deps]:
  git: https://github.com/user/repo.git to=/app/repo
  git: https://github.com/user/repo.git to=/opt/repo branch=develop
  git: https://github.com/user/repo.git to=/opt/repo tag=v1.2.3
"""

from builder.base import Manager


class GitManager(Manager):
    name = "git"
    help_text = "git: URL to=PATH [branch=NAME] [tag=NAME]"

    def parse(self, args: str) -> dict:
        """
        Parse git syntax: 'https://... to=/path branch=main'

        Returns:
          {
            "url": "https://...",
            "to": "/app/repo",
            "branch": "main",  # optional
            "tag": "v1.0",     # optional
            "depth": 0,        # optional
          }
        """
        tokens = args.split(maxsplit=1)
        if not tokens:
            raise ValueError("git: requires repository URL")

        url = tokens[0]
        if not url.startswith("http"):
            raise ValueError(f"git: invalid URL '{url}'")

        options = {}
        if len(tokens) > 1:
            # Parse remaining tokens as key=value
            for token in tokens[1].split():
                if "=" in token:
                    key, val = token.split("=", 1)
                    options[key] = val

        if "to" not in options:
            raise ValueError("git: 'to=PATH' is required")

        return {
            "url": url,
            "to": options["to"],
            "branch": options.get("branch"),
            "tag": options.get("tag"),
            "depth": options.get("depth", 0),
        }

    def install(self, rootfs: str, parsed: dict) -> list[str]:
        """Generate git clone commands."""
        url = parsed["url"]
        to = parsed["to"]
        branch = parsed.get("branch")
        tag = parsed.get("tag")
        depth = parsed.get("depth", 0)

        cmd = f"git clone {url} {to}"

        if branch:
            cmd += f" --branch {branch}"
        elif tag:
            cmd += f" --branch {tag}"

        if depth and depth != "0":
            cmd += f" --depth {depth}"

        return [cmd]