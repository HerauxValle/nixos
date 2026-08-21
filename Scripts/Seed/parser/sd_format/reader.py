"""
core/sd_format/reader.py — read and verify .sdl/.sdx/.sdp files
"""

from common.emit import emit

import os
import json
import struct
import hashlib
import subprocess
import platform
from lib.variables.general import *



def _kernel_version_ok(file_kernel: str) -> bool:
    """Check if file's kernel version is compatible with current kernel."""
    def _parse(v): return tuple(int(x) for x in v.split("-")[0].split(".")[:2])
    try:
        current = _parse(platform.release())
        source  = _parse(file_kernel)
        return current >= source
    except Exception:
        return True  # assume ok if can't parse


def read_header(path: str) -> dict:
    """Read and return header from an SD file without extracting data."""
    with open(path, "rb") as f:
        magic = f.read(4)
        if magic != SD_MAGIC:
            from common.errors import error
            error("INVALID_FILE", "not a valid SD file", path)
        header_len = struct.unpack(">I", f.read(4))[0]
        header     = json.loads(f.read(header_len).decode("utf-8"))
    return header


def verify(path: str) -> bool:
    """Verify checksum of SD file data block."""
    with open(path, "rb") as f:
        f.read(4)                                          # magic
        header_len  = struct.unpack(">I", f.read(4))[0]
        f.read(header_len)                                 # header
        data_len    = struct.unpack(">Q", f.read(8))[0]
        data        = f.read(data_len)
        stored_hash = f.read(32)

    return hashlib.sha256(data).digest() == stored_hash


def extract(path: str, dest_subvol: str) -> dict:
    """
    Verify and extract SD file into a btrfs subvol.
    Returns the header metadata.
    """
    from common.errors import error

    header = read_header(path)

    # kernel compatibility check
    file_kernel = header.get("kernel_version", "0.0")
    if not _kernel_version_ok(file_kernel):
        error("KERNEL_INCOMPATIBLE",
              f"file was created on kernel {file_kernel}",
              f"current kernel: {platform.release()}",
              "this file may use unsupported btrfs features")

    if not verify(path):
        error("CHECKSUM_FAILED", "SD file checksum mismatch — file may be corrupt", path)

    emit("log", f"extracting {path} → {dest_subvol}...")

    with open(path, "rb") as f:
        f.read(4)
        header_len = struct.unpack(">I", f.read(4))[0]
        f.read(header_len)
        data_len   = struct.unpack(">Q", f.read(8))[0]
        data       = f.read(data_len)

    # decompress + btrfs receive
    zstd_proc = subprocess.Popen(
        ["zstd", "-d", "-q", "-"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE
    )
    recv_proc = subprocess.Popen(
        ["sudo", "btrfs", "receive", os.path.dirname(dest_subvol)],
        stdin=zstd_proc.stdout
    )
    zstd_proc.stdout.close()
    zstd_proc.stdin.write(data)
    zstd_proc.stdin.close()
    recv_proc.wait()

    if recv_proc.returncode != 0:
        from common.errors import error
        error("IMPORT_FAILED", "btrfs receive failed", path)

    emit("log", f"extracted → {dest_subvol}")
    return header