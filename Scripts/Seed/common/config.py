"""
common/config.py — config file resolution via shebang scanning
"""

import os
import shutil

from common.shebang import find, scan_dir, list_dir, read_shebangs
from lib.variables.general import PROJECT_CONFIG, KNOWN_SHEBANGS, IMG_DYNAMIC_DIRS
from lib.variables.general import *


# folders created inside .img on create/select


def get_config_path(shebang: str) -> str:
    """Find config file by shebang. Img first, project fallback."""
    from common.errors import error

    dirs = []
    try:
        from common.session import get_active
        dirs.append(os.path.join(get_active(), "config"))
    except Exception:
        pass
    dirs.append(PROJECT_CONFIG)

    path = find(shebang, *dirs)
    if path:
        return path

    error("CONFIG_NOT_FOUND", f"no config file with shebang '#{shebang}' found",
          "check config/ in your img and project root")


def get_rule(key: str):
    """Shortcut — delegates to core.settings."""
    from orchestration.settings import get_rule as _get
    return _get(key)


def regenerate_missing(mnt: str) -> None:
    """Copy project config files missing from img config/. Create dynamic dirs."""
    img_config = os.path.join(mnt, "config")
    os.makedirs(img_config, exist_ok=True)
    img_shebangs = set(scan_dir(img_config).keys())

    for root, _, files in os.walk(PROJECT_CONFIG):
        for f in files:
            src      = os.path.join(root, f)
            shebangs = read_shebangs(src)
            if any(sb not in img_shebangs for sb in shebangs if sb in KNOWN_SHEBANGS):
                rel = os.path.relpath(src, PROJECT_CONFIG)
                dst = os.path.join(img_config, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)

    # ensure dynamic dirs exist
    for d in IMG_DYNAMIC_DIRS:
        os.makedirs(os.path.join(mnt, d), exist_ok=True)


def reset_config(mnt: str) -> None:
    """Wipe img config/ and copy everything from project config/."""
    img_config = os.path.join(mnt, "config")
    if os.path.isdir(img_config):
        shutil.rmtree(img_config)
    os.makedirs(img_config)
    for root, _, files in os.walk(PROJECT_CONFIG):
        for f in files:
            src = os.path.join(root, f)
            rel = os.path.relpath(src, PROJECT_CONFIG)
            dst = os.path.join(img_config, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)


def list_configs(mnt: str) -> list[dict]:
    img_config = os.path.join(mnt, "config")
    return list_dir(img_config, known=KNOWN_SHEBANGS)