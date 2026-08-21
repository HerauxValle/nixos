"""
core/network/dns.py — /etc/hosts injection for service name resolution
Writes all sibling container IPs into each container's /etc/hosts.
"""

import os


def write_hosts(rootfs: str, container_ip: str,
                hostname: str, peers: dict[str, str]) -> None:
    """
    Write /etc/hosts inside container rootfs.
    peers = {service_name: ip} for all containers in same img.
    """
    hosts_path = os.path.join(rootfs, "etc", "hosts")
    os.makedirs(os.path.dirname(hosts_path), exist_ok=True)

    lines = [
        "127.0.0.1   localhost",
        "::1         localhost",
        f"{container_ip}   {hostname}",
        "",
        "# SD container network",
    ]
    for name, ip in sorted(peers.items()):
        if ip != container_ip:
            lines.append(f"{ip}   {name}")

    with open(hosts_path, "w") as f:
        f.write("\n".join(lines) + "\n")


def update_all_hosts(mnt: str, rootfs_map: dict[str, str],
                     ip_map: dict[str, str]) -> None:
    """
    Refresh /etc/hosts in ALL running containers after a new one joins.
    rootfs_map = {container_name: rootfs_path}
    ip_map     = {container_name: ip}
    """
    for name, rootfs in rootfs_map.items():
        ip = ip_map.get(name)
        if ip and os.path.isdir(rootfs):
            write_hosts(rootfs, ip, name, ip_map)