"""
core/network/forward.py — iptables MASQUERADE + DNAT port forwarding
All rules tagged with --comment sd:<img_id> for clean teardown.
"""

import subprocess
import os


def _sudo(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["sudo"] + cmd, capture_output=True, text=True,
        timeout=60, check=check
    )


def _img_tag(mnt: str) -> str:
    """Stable tag — reads network_tag from img meta (stable across remounts)."""
    try:
        import tomllib
        with open(os.path.join(mnt, "meta.toml"), "rb") as f:
            meta = tomllib.load(f)
        if "network_tag" in meta:
            return meta["network_tag"]
    except Exception:
        pass
    return f"sd:{os.path.basename(mnt)}"


def _ipt(table: str, chain: str, rule: list[str],
         action: str = "-A", check: bool = True) -> subprocess.CompletedProcess:
    return _sudo(["iptables", "-t", table, action, chain] + rule, check=check)


# ── outbound masquerade ───────────────────────────────────────────────────────

def enable_localnet_routing() -> None:
    """Allow DNAT to localhost — required for localhost:port → container forwarding."""
    _sudo(["sysctl", "-w", "net.ipv4.conf.all.route_localnet=1"], check=False)


def add_masquerade(mnt: str, subnet: str, bridge: str) -> None:
    """MASQUERADE outbound + bridge-local traffic for host→container via localhost."""
    tag = _img_tag(mnt)
    # outbound from containers to internet
    _ipt("nat", "POSTROUTING", [
        "-s", subnet, "!", "-o", "lo",
        "-j", "MASQUERADE",
        "-m", "comment", "--comment", tag,
    ])
    # host-originated traffic going into bridge (enables localhost:port forwarding)
    _ipt("nat", "POSTROUTING", [
        "-o", bridge,
        "-j", "MASQUERADE",
        "-m", "comment", "--comment", tag,
    ])


def del_masquerade(mnt: str, subnet: str, bridge: str) -> None:
    tag = _img_tag(mnt)
    _ipt("nat", "POSTROUTING", [
        "-s", subnet, "!", "-o", "lo",
        "-j", "MASQUERADE",
        "-m", "comment", "--comment", tag,
    ], action="-D", check=False)
    _ipt("nat", "POSTROUTING", [
        "-o", bridge,
        "-j", "MASQUERADE",
        "-m", "comment", "--comment", tag,
    ], action="-D", check=False)


# ── port forwarding ───────────────────────────────────────────────────────────

def add_port_forward(mnt: str, host_port: int,
                     container_ip: str, container_port: int,
                     proto: str = "tcp") -> None:
    """DNAT host_port → container_ip:container_port."""
    from common.emit import emit
    tag = _img_tag(mnt)
    emit("log", f"[forward] adding DNAT: {host_port} → {container_ip}:{container_port}/{proto}")
    # DNAT in nat/PREROUTING
    _ipt("nat", "PREROUTING", [
        "-p", proto, "--dport", str(host_port),
        "-j", "DNAT", "--to-destination",
        f"{container_ip}:{container_port}",
        "-m", "comment", "--comment", tag,
    ])
    # also handle localhost access via OUTPUT chain
    _ipt("nat", "OUTPUT", [
        "-p", proto, "--dport", str(host_port),
        "-j", "DNAT", "--to-destination",
        f"{container_ip}:{container_port}",
        "-m", "comment", "--comment", tag,
    ])
    # allow forwarded traffic
    _ipt("filter", "FORWARD", [
        "-p", proto, "-d", container_ip,
        "--dport", str(container_port),
        "-j", "ACCEPT",
        "-m", "comment", "--comment", tag,
    ])


def del_port_forward(mnt: str, host_port: int,
                     container_ip: str, container_port: int,
                     proto: str = "tcp") -> None:
    tag = _img_tag(mnt)
    for table, chain, rule in [
        ("nat", "PREROUTING", ["-p", proto, "--dport", str(host_port),
                                "-j", "DNAT", "--to-destination",
                                f"{container_ip}:{container_port}",
                                "-m", "comment", "--comment", tag]),
        ("nat", "OUTPUT",     ["-p", proto, "--dport", str(host_port),
                                "-j", "DNAT", "--to-destination",
                                f"{container_ip}:{container_port}",
                                "-m", "comment", "--comment", tag]),
        ("filter", "FORWARD", ["-p", proto, "-d", container_ip,
                                "--dport", str(container_port),
                                "-j", "ACCEPT",
                                "-m", "comment", "--comment", tag]),
    ]:
        _ipt(table, chain, rule, action="-D", check=False)


# ── bulk cleanup by tag ───────────────────────────────────────────────────────

def cleanup_all(mnt: str) -> None:
    """
    Remove ALL iptables rules tagged with this img's tag.
    Called by sd close — safe even if rules don't exist.
    """
    tag = _img_tag(mnt)
    for table in ("nat", "filter"):
        # loop until no more matching rules (handles duplicates)
        while True:
            result = _sudo(["iptables", "-t", table, "-S"], check=False)
            deleted = False
            for line in result.stdout.splitlines():
                if tag in line and line.startswith("-A "):
                    # -A CHAIN rule... → iptables -t table -D CHAIN rule...
                    parts  = line[3:].split(None, 1)  # ["CHAIN", "rest of rule"]
                    chain  = parts[0]
                    rest   = parts[1] if len(parts) > 1 else ""
                    import shlex
                    _sudo(["iptables", "-t", table, "-D", chain] + shlex.split(rest),
                          check=False)
                    deleted = True
                    break  # restart scan after each deletion
            if not deleted:
                break


# ── userspace proxy ──────────────────────────────────────────────────────────────

def spawn_proxy(mnt: str, container_name: str,
                host_port: int, container_ip: str, container_port: int) -> int:
    """Spawn a Python proxy process. Returns PID."""
    import subprocess, sys
    proxy_script = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "proxy.py"
    )
    proc = subprocess.Popen(
        [sys.executable, proxy_script,
         str(host_port), container_ip, str(container_port)],
        start_new_session=True,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    from common.process import track
    track(proc.pid, f"proxy-{container_name}-{host_port}", kind="proxy",
          parent=container_name)
    return proc.pid


def kill_proxy(container_name: str, host_port: int) -> None:
    """Kill proxy process for a container port."""
    import signal as _sig
    from common.process import untrack, list_tracked
    name = f"proxy-{container_name}-{host_port}"
    for p in list_tracked():
        if p["name"] == name:
            try: os.kill(p["pid"], _sig.SIGTERM)
            except Exception: pass
            untrack(name)
            return


# ── port conflict detection ───────────────────────────────────────────────────

def check_port_conflict(host_port: int) -> bool:
    """True if host_port is already bound on host."""
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("0.0.0.0", host_port))
        s.close()
        return False
    except OSError:
        return True


def parse_port(port_str: str) -> tuple[int, int, str]:
    """
    Parse port spec: "11434:11434" or "11434:11434/udp"
    Returns (host_port, container_port, proto)
    """
    proto = "tcp"
    if "/" in port_str:
        port_str, proto = port_str.rsplit("/", 1)
    parts = port_str.split(":")
    if len(parts) == 2:
        return int(parts[0]), int(parts[1]), proto
    p = int(parts[0])
    return p, p, proto