#!/usr/bin/env python3
import ipaddress
import json
import socket
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HISTORY_FILE = Path("/var/lib/port-forwarding/ip-history.json")
MAX = 10


def detect_usable_ips():
    ips = []
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            primary = s.getsockname()[0]
        if primary and not ipaddress.ip_address(primary).is_loopback:
            ips.append(primary)
    except Exception:
        pass
    try:
        result = subprocess.run(["ip", "-4", "-o", "addr", "show"], capture_output=True, text=True, check=True)
        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) < 4 or parts[1] == "lo":
                continue
            ip = parts[3].split("/")[0]
            try:
                if not ipaddress.ip_address(ip).is_loopback and ip not in ips:
                    ips.append(ip)
            except ValueError:
                pass
    except Exception:
        pass
    return ips


def detect_public_ipv6():
    addrs = []
    try:
        result = subprocess.run(
            ["ip", "-6", "-o", "addr", "show", "scope", "global"], capture_output=True, text=True, check=True
        )
        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) < 4 or parts[1] == "lo":
                continue
            ip = parts[3].split("/")[0]
            try:
                a = ipaddress.ip_address(ip)
                if not a.is_private and not a.is_loopback and ip not in addrs:
                    addrs.append(ip)
            except ValueError:
                pass
    except Exception:
        pass
    return addrs


def load():
    try:
        return json.loads(HISTORY_FILE.read_text())
    except Exception:
        return {"ipv4": [], "ipv6": []}


def save(hist):
    HISTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
    HISTORY_FILE.write_text(json.dumps(hist, indent=2))
    HISTORY_FILE.chmod(0o644)


def record():
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    cur_v4, cur_v6 = detect_usable_ips(), detect_public_ipv6()
    hist = load()
    changed_v4 = changed_v6 = False
    last_v4 = hist["ipv4"][-1]["ips"] if hist["ipv4"] else None
    last_v6 = hist["ipv6"][-1]["ips"] if hist["ipv6"] else None
    if cur_v4 != last_v4:
        hist["ipv4"].append({"ts": now, "ips": cur_v4})
        hist["ipv4"] = hist["ipv4"][-MAX:]
        changed_v4 = True
    if cur_v6 != last_v6:
        hist["ipv6"].append({"ts": now, "ips": cur_v6})
        hist["ipv6"] = hist["ipv6"][-MAX:]
        changed_v6 = True
    if changed_v4 or changed_v6:
        save(hist)
    return changed_v4, changed_v6, cur_v4, cur_v6


def cmd_changed():
    changed_v4, changed_v6, cur_v4, cur_v6 = record()
    if not (changed_v4 or changed_v6):
        print("still the same")
        return
    if changed_v4:
        print(f"ipv4 changed -> {', '.join(cur_v4) or 'none'}")
    if changed_v6:
        print(f"ipv6 changed -> {', '.join(cur_v6) or 'none'}")


def cmd_show(kind, last_n):
    entries = load().get(kind, [])[-last_n:]
    if not entries:
        print(f"no {kind} history recorded yet -- run 'port-forwarding history changed' first")
        return
    for e in reversed(entries):
        ips = ", ".join(e["ips"]) if e["ips"] else "none"
        print(f"{e.get('ts', '?')}  {ips}")


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "record"
    if cmd == "record":
        record()
    elif cmd == "changed":
        cmd_changed()
    elif cmd in ("ipv4", "ipv6"):
        last_n = MAX
        for a in args[1:]:
            if a.startswith("--last"):
                last_n = min(int(a.split(":", 1)[1]), MAX) if ":" in a else 3
        cmd_show(cmd, last_n)
    else:
        print("usage: port-forwarding history [record|changed|ipv4|ipv6 [--last:N]]", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
