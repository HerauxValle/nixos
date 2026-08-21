"""
builder/discovery.py — Manager auto-discovery
"""

import os
import importlib
from .base import Manager


_managers = {}


def _load_managers():
    """Auto-discover and load all manager plugins"""
    global _managers
    managers_dir = os.path.join(os.path.dirname(__file__), 'managers')

    for filename in os.listdir(managers_dir):
        if filename.startswith('_') or not filename.endswith('.py'):
            continue

        module_name = filename[:-3]
        try:
            module = importlib.import_module(f'builder.managers.{module_name}')
            for attr_name in dir(module):
                attr = getattr(module, attr_name)
                if (isinstance(attr, type) and issubclass(attr, Manager) and
                    attr is not Manager and hasattr(attr, 'name') and attr.name):
                    manager_instance = attr()
                    _managers[attr.name] = manager_instance
        except Exception:
            pass


def get_manager(name: str) -> Manager | None:
    """Get a manager instance by name (e.g., 'pip', 'npm', 'git')"""
    if not _managers:
        _load_managers()
    return _managers.get(name)


_load_managers()
