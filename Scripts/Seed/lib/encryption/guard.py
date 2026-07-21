"""
lib/encryption/guard.py — Lockout prevention checks
Validates that operations won't result in user lockout.
"""

from lib.encryption.slots import (
    count_active_user_slots, get_verified_slots, list_all_slots
)
from lib.encryption.luks import dump
from lib.encryption.keyfile import keyfile_exists


def check_safe_to_remove_slot(mnt: str, img_path: str) -> None:
    """
    Check A: Safe to remove a user slot?
    At least 1 slot in 7–31 must remain active, OR slot 0 must be active.
    Raises error if unsafe.
    """
    from lib.variables.general import SLOT_HARDCODED
    from common.errors import error

    # After removal, how many user slots remain?
    current_count = count_active_user_slots(mnt)
    if current_count <= 1:
        # Removing this would be the last one
        luks_state = dump(img_path)
        slot0_active = (
            luks_state and SLOT_HARDCODED in luks_state.get("active_slots", [])
        )
        if not slot0_active:
            error(
                "LOCKOUT_RISK",
                "cannot remove the last user slot without an active hardcoded key",
                "add another key first, or enable the hardcoded key"
            )


def check_safe_to_add_slot(mnt: str) -> None:
    """
    Check B: Safe to add a user slot?
    At least 1 free slot must exist in 7–31.
    Raises error if no free slots.
    """
    from lib.encryption.slots import find_free_slot
    from common.errors import error

    free_slot = find_free_slot(mnt)
    if free_slot is None:
        error(
            "NO_FREE_SLOTS",
            "all 25 user slots (7–31) are in use",
            "delete an unused key first"
        )


def check_safe_to_enable(mnt: str) -> None:
    """
    Check C: Safe to enable encryption (remove slot 0)?
    At least 1 active slot in 7–31 must exist.
    Raises error if would result in lockout.
    """
    from common.errors import error

    if count_active_user_slots(mnt) == 0:
        error(
            "NO_USER_KEYS",
            "cannot enable encryption without at least one user key",
            "add a passkey or verified system first"
        )


def check_safe_to_refresh_auth(mnt: str, img_path: str) -> None:
    """
    Check D: Safe to run refresh auth?
    Both keyfile_a and keyfile_b must exist and be active in LUKS.
    Raises error if either is missing.
    """
    from lib.variables.general import SLOT_KEYFILE_A, SLOT_KEYFILE_B
    from common.errors import error

    # Check files exist
    if not keyfile_exists(mnt, "a"):
        error(
            "MISSING_KEYFILE",
            "keyfile_a not found",
            "manually add it using any active passkey: cryptsetup luksAddKey --key-slot 1 <img>"
        )

    if not keyfile_exists(mnt, "b"):
        error(
            "MISSING_KEYFILE",
            "keyfile_b not found",
            "manually add it using any active passkey: cryptsetup luksAddKey --key-slot 2 <img>"
        )

    # Check LUKS slots are active
    luks_state = dump(img_path)
    if not luks_state:
        error("LUKS_ERROR", "could not read LUKS header")

    active_slots = luks_state.get("active_slots", [])
    if SLOT_KEYFILE_A not in active_slots:
        error(
            "KEYFILE_NOT_ACTIVE",
            "slot 1 (keyfile_a) not active in LUKS",
            "manually add it using any active passkey"
        )

    if SLOT_KEYFILE_B not in active_slots:
        error(
            "KEYFILE_NOT_ACTIVE",
            "slot 2 (keyfile_b) not active in LUKS",
            "manually add it using any active passkey"
        )


def check_slot_is_user_slot(slot_num: int) -> None:
    """Validate that slot number is in user range (7–31)."""
    from common.errors import error

    if not (7 <= slot_num <= 31):  # User slots: 7-31
        error(
            "SYSTEM_SLOT",
            f"slot {slot_num} is a system slot and cannot be modified",
            "use slots 7–31"
        )


def check_no_ambiguous_names(mnt: str, name: str) -> None:
    """
    Check for name ambiguity. If multiple slots match, error with list.
    """
    from lib.encryption.slots import list_matching_slots
    from common.errors import error

    matching = list_matching_slots(mnt, name)
    if len(matching) > 1:
        slots_str = ", ".join(str(num) for num, _ in matching)
        error(
            "AMBIGUOUS_NAME",
            f"name '{name}' matches multiple slots: {slots_str}",
            "use slot number instead"
        )
