"""
engine/image/header.py — read/write .img binary headers
Header is written at offset 0, before LUKS setup.
Stays outside LUKS encrypted region (LUKS offset is 8 × 512-byte sectors = 4096 bytes).
"""

import os
import struct
import time
import uuid
from dataclasses import dataclass

from lib.variables.general import (
    IMG_HEADER_MAGIC,
    IMG_HEADER_VERSION,
    IMG_HEADER_SIZE,
    IMG_HEADER_OFFSET,
)

_PACK_FMT = ">7sBBQ16s"  # magic(7) + version(1) + priority(1) + last_used(8) + uuid(16) = 34 bytes


@dataclass
class ImgHeader:
    version: int
    priority: int
    last_used: int  # unix timestamp; 0 = never
    uid: bytes


def write_header(path: str, priority: int = 0) -> None:
    """
    Write a fresh 4096-byte header at offset 1MB of path.
    (Offset 0 is reserved for LUKS header; we write at 1MB which is after LUKS metadata)
    Call immediately after LUKS setup, after cryptsetup luksFormat.
    """
    uid = uuid.uuid4().bytes
    packed = struct.pack(
        _PACK_FMT,
        IMG_HEADER_MAGIC,
        IMG_HEADER_VERSION,
        priority,
        0,  # last_used = never
        uid,
    )
    header = packed + b"\x00" * (IMG_HEADER_SIZE - len(packed))
    with open(path, "r+b") as f:
        f.seek(IMG_HEADER_OFFSET)
        f.write(header)


def read_header(path: str) -> ImgHeader | None:
    """
    Read and parse header from path at offset IMG_HEADER_OFFSET (1MB).
    Returns None if invalid or unreadable.
    Safe to call on any file.
    """
    try:
        with open(path, "rb") as f:
            f.seek(IMG_HEADER_OFFSET)
            raw = f.read(33)  # 7+1+1+8+16 = 33 bytes
        if len(raw) < 33:
            return None
        magic, version, priority, last_used, uid = struct.unpack(_PACK_FMT, raw)
        if magic != IMG_HEADER_MAGIC or version != IMG_HEADER_VERSION:
            return None
        return ImgHeader(version, priority, last_used, uid)
    except (OSError, struct.error):
        return None


def update_last_used(path: str) -> None:
    """
    Update the LAST_USED field (offset IMG_HEADER_OFFSET+15, 8 bytes) with current unix time.
    Call after successful img selection.
    Catches OSError silently — never raises.
    """
    try:
        now = int(time.time())
        with open(path, "r+b") as f:
            f.seek(IMG_HEADER_OFFSET + 15)
            f.write(struct.pack(">Q", now))
    except OSError as e:
        from common.emit import emit
        emit("warning", f"could not update img header: {e}")
