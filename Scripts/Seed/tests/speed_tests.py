#!/usr/bin/env python3
import subprocess
import sys
import time
import statistics
import tempfile
import os

# === CONFIG ===
PROJECT_ROOT = os.path.expanduser("~/Projects/Seed")
TARGET = "main"
RUNS = 5
# ==============


ENV = os.environ.copy()
ENV["PYTHONPATH"] = PROJECT_ROOT + (
    ":" + ENV["PYTHONPATH"] if "PYTHONPATH" in ENV else ""
)


def measure_total_time():
    times = []
    for _ in range(RUNS):
        start = time.perf_counter()
        subprocess.run(
            [sys.executable, "-c", f"import {TARGET}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=ENV,
        )
        times.append(time.perf_counter() - start)
    return times


def importtime_profile():
    import re

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        path = tmp.name

    cmd = f"{sys.executable} -X importtime -c 'import {TARGET}'"
    with open(path, "w") as f:
        subprocess.run(cmd, shell=True, stderr=f, env=ENV)

    pattern = re.compile(r"import time:\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(.+)")
    entries = []

    with open(path) as f:
        for line in f:
            m = pattern.search(line)
            if not m:
                continue
            self_time = int(m.group(1))
            cumulative = int(m.group(2))
            module = m.group(3).strip()
            entries.append((cumulative, self_time, module))

    os.unlink(path)
    return sorted(entries, reverse=True)


def module_count():
    code = f"import {TARGET}, sys; print(len(sys.modules))"
    result = subprocess.run(
        [sys.executable, "-c", code],
        capture_output=True,
        text=True,
        env=ENV,
    )
    try:
        return int(result.stdout.strip())
    except:
        return -1


def main():
    print(f"[*] Project root: {PROJECT_ROOT}")
    print(f"[*] Target: {TARGET}")
    print(f"[*] Runs: {RUNS}\n")

    times = measure_total_time()
    print("[+] Startup time (seconds):")
    print(" ", " ".join(f"{t:.4f}" for t in times))
    print(f"  avg: {statistics.mean(times):.4f}")
    print(f"  min: {min(times):.4f}")
    print(f"  max: {max(times):.4f}\n")

    print(f"[+] Modules loaded: {module_count()}\n")

    print("[+] Slowest imports (cumulative µs):")
    for cum, self_t, mod in importtime_profile()[:20]:
        print(f"{cum:>10}  {self_t:>8}  {mod}")

    print("\n[done]")


if __name__ == "__main__":
    main()