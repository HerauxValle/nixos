"""
core/img/create.py — creates a new .img file
"""

from common.emit import emit

import os
import re
import subprocess
import datetime
import shutil
from lib.variables.general import *
from lib.privilege import losetup, cryptsetup, mkfs, mount, umount, chown




def _run(cmd: list[str], input: str = None) -> subprocess.CompletedProcess:
    result = subprocess.run(cmd, input=input, capture_output=True, text=True)
    if result.returncode != 0:
        from common.errors import error
        error("CMD_FAILED", f"{cmd[0]} {cmd[1]}", result.stderr.strip())
    return result


def _img_name(path: str) -> str:
    return os.path.splitext(os.path.basename(path))[0]


def _write_meta(path: str, name: str, created: str, mapper: str, mnt: str, img_path: str = "") -> None:
    with open(path, "w") as f:
        f.write(
            f'name     = "{name}"\n'
            f'created  = "{created}"\n'
            f'mapper   = "{mapper}"\n'
            f'mnt      = "{mnt}"\n'
            f'img_path = "{img_path}"\n'
            f'hash     = ""\n'
        )


def parse_size(raw: str) -> int:
    """Parse a size string into MiB. Accepts: 50, 50mib, 50gib, 50tib, 50mb, 50gb etc."""
    from common.errors import error

    m = re.fullmatch(r"(\d+(?:\.\d+)?)\s*([a-zA-Z]*)", raw.strip())
    if not m:
        error("INVALID_SIZE", "invalid size format", raw)

    value = float(m.group(1))
    unit  = m.group(2).lower()

    UNITS = {
        "":    1,
        "mib": 1,
        "mb":  1,
        "m":   1,
        "gib": 1024,
        "gb":  1024,
        "g":   1024,
        "tib": 1024 * 1024,
        "tb":  1024 * 1024,
        "t":   1024 * 1024,
        "kib": 1 / 1024,
        "kb":  1 / 1024,
        "k":   1 / 1024,
    }

    if unit not in UNITS:
        error("INVALID_SIZE", f"unknown unit '{unit}'", "use: mib, gib, tib, mb, gb, tb")

    return max(1, int(value * UNITS[unit]))


def _resolve_size(path: str, requested: int | None) -> int:
    if requested:
        return requested
    free = shutil.disk_usage(os.path.dirname(path) or ".").free // (1024 * 1024)
    for size in AUTO_SIZES_MIB:
        if free >= size + 1024:
            return size
    from common.errors import error
    error("DISK_FULL", "not enough free disk space", "need at least 5GiB free")


def create(path: str, size_mb: int = None, compress: bool = False) -> None:
    from common.errors import error

    path        = os.path.abspath(path)
    name        = _img_name(path)
    ts          = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    mapper_name = f"sd_{ts}"
    mapper      = f"/dev/mapper/{mapper_name}"
    mnt         = f"{MNT_BASE}/{ts}"
    size        = _resolve_size(path, size_mb)

    if os.path.exists(path):
        error("ALREADY_EXISTS", "img already exists", path)

    # Create file only after all validation passes (deferred allocation)
    emit("log", f"allocating sparse {size}MiB → {path}")
    try:
        _run(["truncate", "-s", f"{size}M", path])
    except Exception:
        # Clean up on failure
        if os.path.exists(path):
            os.remove(path)
        raise

    result = losetup("--find", "--show", path)
    loop   = result.stdout.strip()
    emit("log", f"loop device → {loop}")

    try:
        emit("log", "setting up LUKS slot 0...")
        cryptsetup("luksFormat",
                   "--type", "luks2", "--cipher", "aes-xts-plain64",
                   "--key-size", "256", "--iter-time", "1", "--batch-mode", loop,
                   input_text=LUKS_DEFAULT_KEY)
        cryptsetup("open", loop, mapper_name, input_text=LUKS_DEFAULT_KEY)

        # Write header after LUKS setup (at 1MB offset, after LUKS metadata)
        from engine.image.header import write_header
        write_header(path)
        emit("log", "wrote img header")

        try:
            emit("log", "formatting btrfs...")
            mkfs("btrfs", "-f", "-L", name, mapper)

            os.makedirs(mnt, exist_ok=True)
            opts = "compress=zstd" if compress else ""
            mount(mapper, mnt, opts=opts if opts else "")
            chown(os.getuid(), os.getgid(), mnt)

            for folder in IMG_FOLDERS:
                os.makedirs(f"{mnt}/{folder}", exist_ok=True)

            from common.config import regenerate_missing
            regenerate_missing(mnt)
            _write_meta(f"{mnt}/meta.toml", name=name, created=ts, mapper=mapper_name, mnt=mnt, img_path=path)

            # Create internal keyfiles and add to LUKS slots 1/2
            from lib.encryption.keyfile import create_keyfile
            from lib.encryption.luks import add_key as luks_add_key
            import tempfile

            kf_a = create_keyfile(mnt, "a")
            kf_b = create_keyfile(mnt, "b")

            for slot, kf_bytes in [
                (SLOT_KEYFILE_A, kf_a),
                (SLOT_KEYFILE_B, kf_b),
            ]:
                with tempfile.NamedTemporaryFile(delete=False) as f:
                    f.write(kf_bytes)
                    kf_path = f.name
                try:
                    if not luks_add_key(loop, slot, auth_passphrase=LUKS_DEFAULT_KEY, new_keyfile=kf_path):
                        raise RuntimeError(f"failed to add keyfile to LUKS slot {slot}")
                finally:
                    os.remove(kf_path)

            emit("log", "created internal keyfiles (LUKS slots 1-2)")

            from common.session import write_session
            write_session(mnt)
            emit("action", "created", name)
            emit("action", "selected", name)

        except Exception:
            umount(mnt)
            raise

    except Exception:
        cryptsetup("close", mapper_name, check=False)
        losetup("-d", loop, check=False)
        # Clean up partial img on failure (E3: disk full)
        if os.path.exists(path):
            try:
                os.remove(path)
                emit("log", f"cleaned up partial image: {path}")
            except OSError:
                pass
        raise