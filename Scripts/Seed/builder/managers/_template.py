"""
Template for creating new dependency managers.

Copy this file to a new name (e.g., cargo.py) and implement the three methods.
The manager will be auto-discovered immediately.
"""

from builder.base import Manager


class TemplateManager(Manager):
    # Required: name used in [deps]: blocks (e.g., "pip:", "cargo:")
    name = "template"

    # Optional: short help text
    help_text = "template: package1 package2 [options]"

    def parse(self, args: str) -> dict:
        """
        Parse the manager-specific syntax.

        Args:
            args: The arguments after the colon. Example: "package1 package2 --flag=value"

        Returns:
            dict: Parsed arguments to be passed to install()

        Example:
            Input:  "torch --index-url=https://download.pytorch.org/whl/cpu"
            Return: {
                "packages": ["torch"],
                "index_url": "https://download.pytorch.org/whl/cpu"
            }
        """
        raise NotImplementedError

    def install(self, rootfs: str, parsed: dict) -> list[str]:
        """
        Generate shell commands to install dependencies.

        Args:
            rootfs: Path to the rootfs (for context, usually not needed)
            parsed: Dict returned by parse()

        Returns:
            list[str]: Shell commands to execute in chroot

        Example:
            Input:  {"packages": ["torch"], "index_url": "https://..."}
            Return: ["pip install --index-url https://... torch"]
        """
        raise NotImplementedError


# Example implementation: RustManager
# Uncomment to use. Then rename file to rust.py and remove this comment.

# class RustManager(Manager):
#     name = "rust"
#     help_text = "rust: crate1 crate2"
#
#     def parse(self, args: str) -> dict:
#         crates = args.split()
#         if not crates:
#             raise ValueError("rust: requires at least one crate")
#         return {"crates": crates}
#
#     def install(self, rootfs: str, parsed: dict) -> list[str]:
#         crates = " ".join(parsed["crates"])
#         return [f"cargo install {crates}"]