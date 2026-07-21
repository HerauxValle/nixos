"""
builder/base.py — Base Manager class
"""

from abc import ABC, abstractmethod


class Manager(ABC):
    """Base class for dependency managers (pip, npm, git, etc)"""
    name: str = None
    help_text: str = None

    @abstractmethod
    def parse(self, args: str) -> dict:
        """Parse manager-specific arguments"""
        pass

    @abstractmethod
    def install(self, pkg_manager: str, parsed: dict) -> list[str]:
        """Generate install commands"""
        pass
