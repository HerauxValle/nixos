"""
core/network/manager.py — per-img bridge + IP allocator
One bridge per img, one /24 subnet per img, IPs persist in container meta.

Bridge naming:  sd-br-<img_hash[:8]>
Subnet pool:    10.88.0.0/16 → each img gets a /24 (10.88.N.0/24)
Host IP:        always .1 (bridge itself)
Container IPs:  .2, .3, ... up to .254
"""

import os
import subprocess
import tomllib
from lib.variables.general import FILE_META
from lib.privilege import ip, iptables


# ── subnet pool ───────────────────────────────────────────────────────────────

_POOL_BASE  = "10.88"   # 10.88.0.0/16
_ALLOC_FILE = ".cache/network_alloc.json"  # inside img, tracks used /24 blocks


def _run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


# ── img-level network meta ────────────────────────────────────────────────────

def _read_img_meta(mnt: str) -> dict:
    p = os.path.join(mnt, FILE_META)
    with open(p, "rb") as f:
        return tomllib.load(f)


def _write_img_meta(mnt: str, meta: dict) -> None:
    with open(os.path.join(mnt, FILE_META), "w") as f:
        for k, v in meta.items():
            f.write(f'{k} = "{v}"\n')


# ── bridge management ─────────────────────────────────────────────────────────

def bridge_name(mnt: str) -> str:
    """Deterministic bridge name from img path hash."""
    import hashlib
    h = hashlib.sha256(mnt.encode()).hexdigest()[:8]
    return f"sd-br-{h}"


def bridge_exists(name: str) -> bool:
    r = _run(["ip", "link", "show", name], check=False)
    return r.returncode == 0


def ensure_bridge(mnt: str) -> tuple[str, str]:
    """
    Create bridge for img if not exists.
    Returns (bridge_name, host_ip) e.g. ("sd-br-a3f2c1", "10.88.3.1")
    Persists subnet + bridge in img meta.toml.
    """
    meta   = _read_img_meta(mnt)
    br     = bridge_name(mnt)
    subnet = meta.get("network_subnet", "")

    if not subnet:
        subnet = _alloc_subnet(mnt)
        tag    = f"sd:{br}"   # stable across remounts — based on bridge name not mnt path
        meta["network_bridge"] = br
        meta["network_subnet"] = subnet
        meta["network_tag"]    = tag
        _write_img_meta(mnt, meta)

    host_ip = _subnet_host_ip(subnet)

    if not bridge_exists(br):
        from engine.network.forward import enable_localnet_routing
        enable_localnet_routing()
        _sudo(["ip", "link", "add", br, "type", "bridge"])
        _sudo(["ip", "addr", "add", f"{host_ip}/24", "dev", br])
        _sudo(["ip", "link", "set", br, "up"])
        # enable IP forwarding
        _sudo(["sysctl", "-w", "net.ipv4.ip_forward=1"])
        # disable reverse path filtering on bridge
        _sudo(["sysctl", "-w", f"net.ipv4.conf.{br}.rp_filter=0"], check=False)

    return br, host_ip


def delete_bridge(mnt: str) -> None:
    """Tear down bridge — called by sd close."""
    meta = _read_img_meta(mnt)
    br   = meta.get("network_bridge", bridge_name(mnt))
    if bridge_exists(br):
        _sudo(["ip", "link", "set", br, "down"], check=False)
        _sudo(["ip", "link", "delete", br], check=False)


# ── IP allocation ─────────────────────────────────────────────────────────────

def _alloc_subnet(mnt: str) -> str:
    """Allocate next free /24 block. Persisted in global alloc file."""
    import json
    alloc_path = f"/tmp/simpleDocker/network_alloc.json"
    os.makedirs(os.path.dirname(alloc_path), exist_ok=True)
    try:
        with open(alloc_path) as f:
            alloc = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        alloc = {}

    # find next free block (0–254)
    used = set(alloc.values())
    for n in range(1, 255):
        if n not in used:
            alloc[mnt] = n
            with open(alloc_path, "w") as f:
                json.dump(alloc, f)
            return f"{_POOL_BASE}.{n}.0/24"

    from common.errors import error
    error("NETWORK_EXHAUSTED", "no free /24 subnets available")


def free_subnet(mnt: str) -> None:
    """Release subnet allocation on img delete."""
    import json
    alloc_path = f"/tmp/simpleDocker/network_alloc.json"
    try:
        with open(alloc_path) as f:
            alloc = json.load(f)
        alloc.pop(mnt, None)
        with open(alloc_path, "w") as f:
            json.dump(alloc, f)
    except Exception:
        pass


def _subnet_host_ip(subnet: str) -> str:
    """10.88.3.0/24 → 10.88.3.1"""
    base = subnet.split("/")[0]
    parts = base.rsplit(".", 1)
    return f"{parts[0]}.1"


def _subnet_base(subnet: str) -> str:
    """10.88.3.0/24 → 10.88.3"""
    return subnet.split("/")[0].rsplit(".", 1)[0]


def alloc_container_ip(mnt: str, container_name: str) -> str:
    """
    Allocate next free IP in img subnet for a container.
    Persisted in img .cache/ip_map.json.
    """
    import json
    meta       = _read_img_meta(mnt)
    subnet     = meta.get("network_subnet", "")
    if not subnet:
        ensure_bridge(mnt)
        meta   = _read_img_meta(mnt)
        subnet = meta["network_subnet"]

    ip_map_path = os.path.join(mnt, ".cache", "ip_map.json")
    os.makedirs(os.path.dirname(ip_map_path), exist_ok=True)
    try:
        with open(ip_map_path) as f:
            ip_map = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        ip_map = {}

    # return existing IP if already allocated
    if container_name in ip_map:
        return ip_map[container_name]

    base = _subnet_base(subnet)
    used = set(ip_map.values())
    for n in range(2, 255):
        ip = f"{base}.{n}"
        if ip not in used:
            ip_map[container_name] = ip
            with open(ip_map_path, "w") as f:
                json.dump(ip_map, f)
            return ip

    from common.errors import error
    error("SUBNET_FULL", f"no free IPs in subnet {subnet}")


def free_container_ip(mnt: str, container_name: str) -> None:
    """Release container IP on delete."""
    import json
    ip_map_path = os.path.join(mnt, ".cache", "ip_map.json")
    try:
        with open(ip_map_path) as f:
            ip_map = json.load(f)
        ip_map.pop(container_name, None)
        with open(ip_map_path, "w") as f:
            json.dump(ip_map, f)
    except Exception:
        pass


def get_container_ip(mnt: str, container_name: str) -> str | None:
    """Look up allocated IP for a container."""
    import json
    ip_map_path = os.path.join(mnt, ".cache", "ip_map.json")
    try:
        with open(ip_map_path) as f:
            return json.load(f).get(container_name)
    except Exception:
        return None


def get_all_ips(mnt: str) -> dict[str, str]:
    """Return {container_name: ip} for all containers in img."""
    import json
    ip_map_path = os.path.join(mnt, ".cache", "ip_map.json")
    try:
        with open(ip_map_path) as f:
            return json.load(f)
    except Exception:
        return {}