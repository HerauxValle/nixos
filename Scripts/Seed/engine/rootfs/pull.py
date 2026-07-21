"""
core/rootfs/pull.py — pull rootfs tarballs
Accepts: distro, distro:version, direct URL, or local file path.
All distro URLs live in config/distros.jsonc.
"""

from common.emit import emit

import os
import re
import json
import urllib.request
from lib.variables.general import *
from lib.privilege import chown




def _load_distros() -> dict:
    from common.config  import get_config_path
    from common.io.strip import jsonc as strip_jsonc_comments
    path = get_config_path("distros")
    with open(path, "r", encoding="utf-8") as f:
        text = strip_jsonc_comments(f.read())
    return json.loads(text).get("distros", {})


def _parse_spec(spec: str) -> tuple[str, str]:
    if ":" in spec:
        distro, version = spec.split(":", 1)
    else:
        distro, version = spec, "latest"
    return distro.lower().strip(), version.strip()


def _resolve_url(distro: str, version: str, distros: dict) -> tuple[str, str]:
    from common.errors import error

    if distro not in distros:
        error("UNKNOWN_DISTRO", f"unknown distro '{distro}'",
              f"known: {', '.join(distros.keys())} — or pass a direct URL")

    cfg = distros[distro]

    # direct key match (latest, bookworm, 22.04, etc)
    if version in cfg:
        url  = cfg[version]
        name = f"{distro}-{version}.tar.gz"
        return url, name

    # fallback to versioned template
    if "versioned" in cfg:
        minor = ".".join(version.split(".")[:2])
        url   = cfg["versioned"].format(version=version, minor=minor)
        name  = f"{distro}-{version}.tar.gz"
        return url, name

    known = [k for k in cfg.keys() if k not in ("versioned",)]
    error("UNKNOWN_VERSION", f"unknown version '{version}' for '{distro}'",
          f"known: {', '.join(known)} — or add it to config/distros.jsonc")


def pull(spec: str, mnt: str) -> str:
    cache_dir = os.path.join(mnt, ROOTFS_CACHE_SUBDIR)
    os.makedirs(cache_dir, exist_ok=True)

    # local file
    if os.path.isfile(spec):
        emit("log", f"using local rootfs → {spec}")
        return spec

    # direct URL
    if spec.startswith("http://") or spec.startswith("https://"):
        url      = spec
        filename = url.split("/")[-1].split("?")[0]
        cached   = os.path.join(cache_dir, filename)
    else:
        distros         = _load_distros()
        distro, version = _parse_spec(spec)
        url, filename   = _resolve_url(distro, version, distros)
        cached          = os.path.join(cache_dir, filename)

    if os.path.isfile(cached):
        emit("log", f"rootfs cached → {cached}")
        return cached

    emit("action", "pulling", spec)
    emit("log", f"url → {url}")

    from common.errors import error
    try:
        urllib.request.urlretrieve(url, cached)
        emit("log", f"saved → {cached}")
    except Exception as e:
        if os.path.isfile(cached):
            os.remove(cached)
        error("PULL_FAILED", "download failed", str(e))

    return cached


def extract(tarball: str, dest: str) -> None:
    import subprocess
    os.makedirs(dest, exist_ok=True)
    emit("log", f"extracting {os.path.basename(tarball)} → {dest}")
    subprocess.run(["sudo", "tar", "-xf", tarball, "-C", dest], check=True)
    subprocess.run(chown(os.getuid(), os.getgid(), dest, recursive=True), check=True)
    emit("log", "extraction complete")