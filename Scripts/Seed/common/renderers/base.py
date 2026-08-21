"""
common/renderers/base.py — Renderer ABC + registry
"""
from abc import ABC, abstractmethod
import sys


class Renderer(ABC):
    """Base class for all renderers. render(ir) is the only contract."""

    @abstractmethod
    def render(self, ir: dict, file=sys.stdout) -> None:
        """Render IR dict to output. Must not raise — handle errors internally."""
        ...


# ── renderer registry ─────────────────────────────────────────────────────────

_REGISTRY: dict[str, type] = {}


def register_renderer(name: str, cls: type) -> None:
    """Register a custom renderer. Use via set_mode(name) after registering."""
    assert issubclass(cls, Renderer), f"{cls} must subclass Renderer"
    _REGISTRY[name] = cls


def get_renderer_class(name: str) -> type | None:
    return _REGISTRY.get(name)