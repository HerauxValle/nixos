"""
core/trash/manager.py — async btrfs subvol deletion via .trash/uuid
Moves subvols to .trash/ immediately freeing the name,
letting the kernel clean up async in the background.
"""

from common.emit import emit

import os
import subprocess
import uuid
from lib.privilege import btrfs, mv



def _trash_dir(mnt: str) -> str:
    d = os.path.join(mnt, ".trash")
    os.makedirs(d, exist_ok=True)
    return d


def delete_subvol(path: str, mnt: str) -> None:
    """
    Safely delete a btrfs subvol by moving to .trash first,
    then deleting. Prevents 'Device Busy' on same-name recreate.
    """
    if not os.path.exists(path):
        return

    trash   = _trash_dir(mnt)
    trashed = os.path.join(trash, str(uuid.uuid4()))

    emit("log", f"trashing {path} → {trashed}")
    subprocess.run(mv(path, trashed), check=True)

    # async delete — fire and don't wait
    subprocess.Popen(
        ["sudo", "btrfs", "subvolume", "delete", trashed],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    emit("log", f"queued delete → {trashed}")


def empty_trash(mnt: str) -> int:
    """Synchronously delete everything in .trash. Returns count deleted."""
    trash = _trash_dir(mnt)
    count = 0
    for name in os.listdir(trash):
        path = os.path.join(trash, name)
        try:
            subprocess.run(
                btrfs("subvolume", "delete", path),
                check=True, capture_output=True
            )
            count += 1
        except subprocess.CalledProcessError:
            emit("log", f"could not delete {path} — still busy, skipping")
    return count