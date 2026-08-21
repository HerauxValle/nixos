"""
core/network/veth.py — veth pair creation and attachment
Creates a veth pair: one end on host bridge, one end inside container namespace.
"""

import hashlib
import os
import subprocess
from lib.privilege import ip


def _sudo(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["sudo"] + cmd, capture_output=True, text=True,
        timeout=60, check=check
    )


def setup_veth(container_name: str, pid: int,
               bridge: str, container_ip: str, subnet: str) -> str:
    """
    Create veth pair, attach host end to bridge, move peer into container ns.
    Returns host-side veth name.

    host:      veth-<name[:10]>  → attached to bridge
    container: eth0              → configured with container_ip
    """
    from common.sanitize import safe_pid, safe_name
    safe_name(container_name, "container (veth)")
    safe_pid(pid, "container PID (veth)")

    # hash-based naming avoids collisions at kernel 15-char ifname limit
    _hash = hashlib.sha1(container_name.encode()).hexdigest()[:8]
    host_veth = f"sd-{_hash}"
    peer_veth = f"sp-{_hash}"
    prefix    = subnet.rsplit(".", 1)[0]  # e.g. "10.88.3"
    gw        = f"{prefix}.1"
    mask      = subnet.split("/")[1]      # e.g. "24"

    # clean up stale veth if exists
    _sudo(["ip", "link", "delete", host_veth], check=False)

    # create veth pair
    _sudo(["ip", "link", "add", host_veth, "type", "veth", "peer", "name", peer_veth])

    # attach host end to bridge
    _sudo(["ip", "link", "set", host_veth, "master", bridge])
    _sudo(["ip", "link", "set", host_veth, "up"])

    # move peer into container network namespace
    _sudo(["ip", "link", "set", peer_veth, "netns", str(pid)])

    # configure inside container namespace
    _sudo(["nsenter", "-t", str(pid), "--net", "--",
           "ip", "link", "set", peer_veth, "name", "eth0"])
    _sudo(["nsenter", "-t", str(pid), "--net", "--",
           "ip", "addr", "add", f"{container_ip}/{mask}", "dev", "eth0"])
    _sudo(["nsenter", "-t", str(pid), "--net", "--",
           "ip", "link", "set", "eth0", "up"])
    _sudo(["nsenter", "-t", str(pid), "--net", "--",
           "ip", "link", "set", "lo", "up"])
    _sudo(["nsenter", "-t", str(pid), "--net", "--",
           "ip", "route", "add", "default", "via", gw])

    return host_veth


def teardown_veth(container_name: str) -> None:
    """Remove host-side veth (peer disappears automatically with container ns)."""
    _hash = hashlib.sha1(container_name.encode()).hexdigest()[:8]
    host_veth = f"sd-{_hash}"
    ip("link", "delete", host_veth, check=False)