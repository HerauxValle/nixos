"""
lib/encryption/slots.py — LUKS slot metadata tracking
Stores user-visible slot info in .img/.cache/encryption/slots.json
Only slots 7–31 are tracked here.
"""

import os
import json
from typing import Optional


def _get_slots_file(mnt: str) -> str:
    """Return path to slots.json cache file."""
    return os.path.join(mnt, ".cache", "encryption", "slots.json")


def load_slots(mnt: str) -> dict:
    """Load slots.json. Returns empty dict if missing or unreadable."""
    slots_file = _get_slots_file(mnt)
    if not os.path.isfile(slots_file):
        return {}
    try:
        with open(slots_file, "r") as f:
            return json.load(f)
    except Exception:
        return {}


def save_slots(mnt: str, slots: dict) -> None:
    """Save slots.json. Creates cache dir if needed."""
    cache_dir = os.path.join(mnt, ".cache", "encryption")
    os.makedirs(cache_dir, exist_ok=True)
    slots_file = _get_slots_file(mnt)
    with open(slots_file, "w") as f:
        json.dump(slots, f, indent=2)


def find_free_slot(mnt: str) -> Optional[int]:
    """
    Find lowest available slot in range 7–31.
    Returns None if all slots are full.
    """
    slots = load_slots(mnt)
    for slot_num in range(7, 32):  # User slots: 7-31
        if str(slot_num) not in slots:
            return slot_num
    return None


def get_slot_by_number(mnt: str, slot_num: int) -> Optional[dict]:
    """Get slot metadata by number. Returns None if not found."""
    slots = load_slots(mnt)
    return slots.get(str(slot_num))


def get_slot_by_name(mnt: str, name: str) -> Optional[tuple[int, dict]]:
    """
    Get slot by name (case-sensitive).
    Returns (slot_number, metadata) tuple or None if not found.
    If multiple slots match, returns first found (lowest slot number).
    """
    slots = load_slots(mnt)
    matching = []
    for slot_num_str, metadata in slots.items():
        if metadata.get("name") == name:
            matching.append((int(slot_num_str), metadata))
    if matching:
        matching.sort(key=lambda x: x[0])
        return matching[0]
    return None


def list_matching_slots(mnt: str, name: str) -> list[tuple[int, dict]]:
    """Get all slots matching a name. Used for ambiguity detection."""
    slots = load_slots(mnt)
    matching = []
    for slot_num_str, metadata in slots.items():
        if metadata.get("name") == name:
            matching.append((int(slot_num_str), metadata))
    matching.sort(key=lambda x: x[0])
    return matching


def add_slot(mnt: str, slot_num: int, slot_type: str, name: Optional[str], preset: str) -> None:
    """
    Add a slot entry. slot_type is 'passkey' or 'verified'.
    """
    if not (7 <= slot_num <= 31):  # User slots: 7-31
        from common.errors import error
        error("INVALID_SLOT", f"slot {slot_num} is not a user slot")

    slots = load_slots(mnt)
    slots[str(slot_num)] = {
        "type": slot_type,
        "name": name,
        "preset": preset,
    }
    save_slots(mnt, slots)


def remove_slot(mnt: str, slot_num: int) -> None:
    """Remove a slot entry."""
    slots = load_slots(mnt)
    if str(slot_num) in slots:
        del slots[str(slot_num)]
        save_slots(mnt, slots)


def rename_slot(mnt: str, slot_num: int, new_name: str) -> None:
    """Rename a slot."""
    slots = load_slots(mnt)
    if str(slot_num) in slots:
        slots[str(slot_num)]["name"] = new_name
        save_slots(mnt, slots)


def list_all_slots(mnt: str) -> list[tuple[int, dict]]:
    """Return list of (slot_num, metadata) tuples, sorted by slot number."""
    slots = load_slots(mnt)
    result = [(int(k), v) for k, v in slots.items()]
    result.sort(key=lambda x: x[0])
    return result


def list_slots_by_type(mnt: str, slot_type: str) -> list[tuple[int, dict]]:
    """Filter slots by type ('passkey' or 'verified')."""
    all_slots = list_all_slots(mnt)
    return [(num, meta) for num, meta in all_slots if meta.get("type") == slot_type]


def count_active_user_slots(mnt: str) -> int:
    """Count active slots in range 7–31."""
    return len(list_all_slots(mnt))


def get_verified_slots(mnt: str) -> list[tuple[int, dict]]:
    """Get all verified-system slots."""
    return list_slots_by_type(mnt, "verified")
