"""
core/sd_format/writer.py — write .sdl/.sdx/.sdp files
Format: magic + JSON header + zstd btrfs send stream + sha256 checksum
"""
from common.emit import emit

import os
import json
import struct
import hashlib
import subprocess
import platform
from lib.variables.general import *



def _btrfs_features(subvol_path: str) -> list[str]:
    """Get btrfs feature flags for the filesystem containing subvol_path."""
    try:
        result = subprocess.run(
            ["sudo", "btrfs", "filesystem", "show", subvol_path],
            capture_output=True, text=True
        )
        features = []
        for line in result.stdout.splitlines():
            if "features" in line.lower():
                features = line.split(":")[-1].strip().split()
        return features
    except Exception:
        return []


def write(
    subvol_path: str,
    dest_path:   str,
    sd_type:     str,          # sdl / sdx / sdp
    metadata:    dict,
    parent_path: str = None,   # for incremental send
) -> None:
    """
    Export a btrfs subvol as an SD file.
    metadata: extra fields merged into header (layer_hash, source, etc)
    """
    
    header = {
        "type":           sd_type,
        "version":        SD_VERSION,
        "kernel_version": platform.release(),
        "btrfs_features": _btrfs_features(subvol_path),
        "nodatacow":      metadata.get("nodatacow", False),
        **metadata
    }

    header_bytes = json.dumps(header).encode("utf-8")
    header_len   = struct.pack(">I", len(header_bytes))

    # btrfs send → zstd compress
    send_cmd = ["sudo", "btrfs", "send"]
    if parent_path:
        send_cmd += ["-p", parent_path]
    send_cmd.append(subvol_path)

    emit("log", f"sending {subvol_path}...")
    send_proc = subprocess.Popen(send_cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    zstd_proc = subprocess.Popen(
        ["zstd", "-q", "-"],
        stdin=send_proc.stdout,
        stdout=subprocess.PIPE
    )
    send_proc.stdout.close()
    compressed, _ = zstd_proc.communicate()

    checksum = hashlib.sha256(compressed).digest()

    with open(dest_path, "wb") as f:
        f.write(SD_MAGIC)
        f.write(header_len)
        f.write(header_bytes)
        f.write(struct.pack(">Q", len(compressed)))
        f.write(compressed)
        f.write(checksum)

    emit("log", f"written → {dest_path} ({len(compressed)//1024}KB)")