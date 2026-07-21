"""
lib/sandboxing/backends.py — Pluggable backend selection and management

Architecture:
  SecuritySpec
    ↓
  select_backend(spec) → best available (AppArmor > Landlock > none)
    ↓
  Backend enforces restrictions at runtime

Selection strategy:
  1. Try AppArmor (mature, requires root + kernel support)
  2. Fall back to Landlock (unprivileged, Linux 5.13+)
  3. Fall back to none (unconfined, graceful degradation)

Each backend independently responsible for availability checks.
No errors — system always works, just with different isolation levels.
"""

from common.emit import emit


class BackendSelection:
    """Select best available security backend for a SecuritySpec."""

    BACKEND_PRIORITY = ["apparmor", "landlock", "none"]

    @staticmethod
    def select(spec) -> str:
        """Select backend based on what's available.

        Args:
            spec: SecuritySpec instance

        Returns:
            Backend name: "apparmor", "landlock", or "none"
        """
        # Try AppArmor first
        try:
            from lib.apparmor.manager import AppArmorManager
            manager = AppArmorManager()
            if manager.available():
                emit("log", "[backends] Selected AppArmor (available + preferred)")
                return "apparmor"
        except Exception as e:
            emit("log", f"[backends] AppArmor unavailable: {e}")

        # Try Landlock as fallback
        try:
            from lib.sandboxing.landlock import LandlockEnforcer
            enforcer = LandlockEnforcer()
            if enforcer.available():
                emit("log", "[backends] Selected Landlock (AppArmor unavailable)")
                return "landlock"
        except Exception as e:
            emit("log", f"[backends] Landlock unavailable: {e}")

        # Fallback to none (unconfined)
        emit("log", "[backends] Selected none (no sandboxing available, running unconfined)")
        return "none"

    @staticmethod
    def enforce(backend: str, spec):
        """Apply restrictions using selected backend.

        Args:
            backend: Backend name from select()
            spec: SecuritySpec instance
        """
        if backend == "apparmor":
            try:
                from lib.apparmor.manager import AppArmorManager
                manager = AppArmorManager()
                # Note: AppArmor enforcement happens in engine/container/run.py
                # This is a placeholder for direct enforcement if needed
                emit("log", "[backends] AppArmor enforcement delegated to run.py")
            except Exception as e:
                emit("warn", f"[backends] AppArmor enforcement failed: {e}")

        elif backend == "landlock":
            try:
                from lib.sandboxing.landlock import LandlockEnforcer
                enforcer = LandlockEnforcer()
                enforcer.restrict(spec)
                emit("log", "[backends] Landlock restrictions applied")
            except Exception as e:
                emit("warn", f"[backends] Landlock enforcement failed: {e}")

        elif backend == "none":
            emit("log", "[backends] No sandboxing enforced (unconfined)")

        else:
            emit("warn", f"[backends] Unknown backend: {backend}")
