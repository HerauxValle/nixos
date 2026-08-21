"""
core/builder/managers/pkg.py — system package manager (apt/apk/pacman/etc)

Usage in [deps]:
  pkg: curl git ca-certificates
  pkg: python3-dev build-essential
"""

from builder.base import Manager


class PkgManager(Manager):
    name = "pkg"
    help_text = "pkg: package1 package2 ... (uses system package manager)"

    def parse(self, args: str) -> dict:
        """Parse space-separated package names."""
        packages = [p.strip() for p in args.split() if p.strip()]
        if not packages:
            raise ValueError("pkg: requires at least one package name")
        return {"packages": packages}

    def install(self, rootfs: str, parsed: dict) -> list[str]:
        """Generate chroot commands. Actual pkg manager detected at build time."""
        packages = parsed["packages"]
        pkg_str = " ".join(packages)
        # This is a placeholder — will be replaced by actual manager (apt/apk/etc) at build time
        return [f"__pkg_install__ {pkg_str}"]