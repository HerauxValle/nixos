"""
core/container/run.py — SDX runner
Reuses stopped containers, errors if already running.
Uses sd-init C binary for container initialization (namespace + pivot_root + seccomp + cgroup).
"""

from common.emit import emit

import os
import subprocess
import datetime
import tomllib
from common.process import track
from engine.layer.build    import build, increment_refs
from orchestration.profile.create import ensure_profiles, mount_profile
from lib.variables.general import *
from lib.privilege import btrfs, chown, mount, umount, mkdir
from lib.seccomp.syscall_names import get_syscall_name, get_current_arch, is_known_syscall


# Metadata cache: (path, mtime) -> dict
_metadata_cache = {}


def _run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, **kw)


def _read_meta(path: str) -> dict:
    """Read metadata with mtime-based caching (invalidates on file change)."""
    from common.sanitize import safe_toml_load
    meta_file = os.path.join(path, "meta.toml")

    try:
        mtime = os.path.getmtime(meta_file)
    except OSError:
        return {}

    cache_key = (path, mtime)
    if cache_key in _metadata_cache:
        return _metadata_cache[cache_key]

    data = safe_toml_load(meta_file)
    _metadata_cache[cache_key] = data

    # Prune cache if it grows too large
    if len(_metadata_cache) > 256:
        _metadata_cache.clear()

    return data


def _write_meta(path: str, meta: dict) -> None:
    with open(os.path.join(path, "meta.toml"), "w") as f:
        for k, v in meta.items():
            v_str = "true" if v is True else "false" if v is False else str(v)
            f.write(f'{k} = "{v_str}"\n')


def _find_existing(mnt: str, svc_name: str) -> tuple[str | None, str]:
    cdir = os.path.join(mnt, DIR_CONTAINERS)
    if not os.path.isdir(cdir): return None, ""
    for name in sorted(os.listdir(cdir)):
        path = os.path.join(cdir, name)
        meta = _read_meta(path)
        if meta.get("service") == svc_name:
            return path, meta.get("status", "stopped")
    return None, ""


def _snapshot_subvol(src: str, dst: str) -> None:
    btrfs("subvolume", "snapshot", src, dst)
    chown(os.getuid(), os.getgid(), dst)


def _setup_cgroup(name: str, resources: dict) -> str | None:
    """Create cgroup directory only. Actual assignment happens in init script."""
    from common.sanitize import safe_name
    safe_name(name, "container (cgroup)")

    memory = str(resources.get("memory", ""))
    cpu    = str(resources.get("cpu", ""))

    cgroup_path = f"/sys/fs/cgroup/sd/{name}"
    try:
        subprocess.run(["sudo", "mkdir", "-p", cgroup_path], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True)

        if memory:
            mem = _parse_memory(memory)
            if mem:
                subprocess.run(
                    ["sudo", "tee", f"{cgroup_path}/memory.max"],
                    input=str(mem),
                    text=True,
                    check=True,
                    capture_output=True,
                    close_fds=True,
                )

        if cpu:
            quota = int(float(cpu) * 100000)
            cpu_max = f"{quota} 100000"
            subprocess.run(
                ["sudo", "tee", f"{cgroup_path}/cpu.max"],
                input=cpu_max,
                text=True,
                check=True,
                capture_output=True,
                close_fds=True,
            )

        return cgroup_path
    except subprocess.CalledProcessError as e:
        from common.emit import emit
        emit("log", f"cgroup setup failed: {e.stderr or e}")
        return None
    except Exception as e:
        from common.emit import emit
        emit("log", f"cgroup setup error: {e}")
        return None


def _parse_memory(s: str) -> int | None:
    import re
    m = re.fullmatch(r"(\d+(?:\.\d+)?)\s*([a-zA-Z]*)", s.strip())
    if not m: return None
    v, u = float(m.group(1)), m.group(2).lower()
    mul  = {"": 1, "mb": 1024**2, "mib": 1024**2, "gb": 1024**3, "gib": 1024**3}
    return int(v * mul.get(u, 1))


def _determine_required_capabilities(run) -> list[str]:
    """Determine minimal capability set required by app."""
    required = []

    # cap_net_bind_service: only if app binds to port < 1024
    port = getattr(run, "port", None)
    if port:
        try:
            host_port = int(str(port).split(":")[0])
            if host_port < 1024:
                required.append("NET_BIND_SERVICE")
        except (ValueError, IndexError):
            pass

    # Additional capabilities from explicit config (default: none)
    extra_caps = run.isolation.get("capabilities", {})
    if extra_caps.get("chown"):
        required.append("CHOWN")
    if extra_caps.get("dac_override"):
        required.append("DAC_OVERRIDE")
    if extra_caps.get("setfcap"):
        required.append("SETFCAP")

    return required


def _build_sd_init_cmd(rootfs: str, container_name: str, run, cgroup_path: str | None) -> list[str]:
    """Build command line for sd-init C binary."""
    cmd = ["sudo", "/usr/local/lib/sd/priv/sd-init",
           "--rootfs", rootfs]

    if cgroup_path:
        cmd.extend(["--cgroup", cgroup_path])

    # Capabilities (from dynamic determination)
    for cap in _determine_required_capabilities(run):
        cmd.extend(["--caps", cap])

    # Environment
    for k, v in run.env.items():
        if v is not None and v != "":
            cmd.extend(["--env", f"{k}={v}"])

    # Separator + actual command
    cmd.append("--")

    if run.entrypoint:
        cmd.append(run.entrypoint)
    for line in run.start if hasattr(run, "start") else []:
        if line.strip() and not line.strip().startswith("#"):
            cmd.append(line.strip())

    return cmd




def _setup_network(mnt: str, container_name: str, svc, rootfs: str, pid: int) -> str:
    """Set up veth, iptables, /etc/hosts. Returns container IP or ''."""
    emit("log", f"[setup_network] svc={svc.name}, svc.run={svc.run}, svc.run.port={getattr(svc.run, 'port', 'NO_ATTR')}")
    emit("log", f"[setup_network] Starting network setup for pid {pid}")
    try:
        from engine.network.manager import ensure_bridge, alloc_container_ip, get_all_ips
        from engine.network.veth    import setup_veth
        from engine.network.forward import (add_masquerade, add_port_forward,
                                          check_port_conflict, parse_port,
                                          enable_localnet_routing)
        from engine.network.dns     import write_hosts, update_all_hosts

        with open(os.path.join(mnt, "meta.toml"), "rb") as f:
            img_meta = tomllib.load(f)

        emit("log", f"[setup_network] ensuring bridge")
        br, _        = ensure_bridge(mnt)
        emit("log", f"[setup_network] bridge={br}")

        emit("log", f"[setup_network] allocating IP")
        container_ip = alloc_container_ip(mnt, container_name)
        emit("log", f"[setup_network] ip={container_ip}")

        subnet       = img_meta.get("network_subnet", "10.88.0.0/24")
        emit("log", f"[setup_network] subnet={subnet}")

        emit("log", f"[setup_network] setting up veth")
        setup_veth(container_name, pid, br, container_ip, subnet)
        emit("log", f"network: {container_name} → {container_ip} on {br}")

        emit("log", f"[setup_network] adding masquerade")
        add_masquerade(mnt, subnet, br)
        emit("log", f"[setup_network] masquerade added")

        emit("log", f"[setup_network] enabling localnet routing")
        enable_localnet_routing()
        emit("log", f"[setup_network] localnet routing enabled")

        port_str = svc.run.port
        emit("log", f"[setup_network] port_str={port_str}")
        if port_str:
            emit("log", f"[setup_network] processing ports")
            from engine.network.forward import spawn_proxy
            for ps in (port_str if isinstance(port_str, list) else [port_str]):
                emit("log", f"[setup_network] parsing port spec: {ps}")
                hp, cp, proto = parse_port(str(ps))
                emit("log", f"[setup_network] parsed: {hp}:{cp}/{proto}")
                if check_port_conflict(hp):
                    from common.errors import error
                    error("PORT_CONFLICT", f"host port {hp} already in use")
                emit("log", f"[setup_network] adding port forward")
                add_port_forward(mnt, hp, container_ip, cp, proto)
                emit("log", f"[setup_network] spawning proxy")
                spawn_proxy(mnt, container_name, hp, container_ip, cp)
                emit("log", f"port {hp}:{cp}/{proto} → {container_ip}")

        emit("log", f"[setup_network] getting all IPs")
        all_ips = get_all_ips(mnt)
        emit("log", f"[setup_network] all_ips={all_ips}")

        emit("log", f"[setup_network] writing hosts for {svc.name}")
        write_hosts(rootfs, container_ip, svc.name, all_ips)
        emit("log", f"[setup_network] hosts written")

        emit("log", f"[setup_network] updating all hosts")
        cdir = os.path.join(mnt, DIR_CONTAINERS)
        rootfs_map = {cn: os.path.join(cdir, cn, "rootfs")
                      for cn in os.listdir(cdir)
                      if os.path.isdir(os.path.join(cdir, cn, "rootfs"))}
        emit("log", f"[setup_network] rootfs_map={rootfs_map}")
        update_all_hosts(mnt, rootfs_map, all_ips)
        emit("log", f"[setup_network] all hosts updated")

        emit("log", f"[setup_network] returning container_ip={container_ip}")
        return container_ip
    except Exception as e:
        import traceback
        emit("log", f"network setup failed: {e}")
        emit("log", f"traceback: {traceback.format_exc()}")
        return ""


def _unmount_fs(rootfs: str) -> None:
    """Best-effort unmount of pseudo-filesystems on cleanup."""
    for target in ["run", "tmp", "dev/shm", "dev/pts", "sys", "proc", "dev"]:
        t = os.path.join(rootfs, target)
        if os.path.ismount(t):
            subprocess.run(["sudo", "umount", "-l", t],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _start_container(container_path: str, rootfs: str,
                     svc, mnt: str, container_name: str,
                     layer_id: str = "", layer_path: str = "") -> int:
    from lib.cleanup import register_cleanup
    from common.errors import error
    run = svc.run

    ensure_profiles(svc.name, run.storage, mnt, layer_path=layer_path)
    for node in run.storage:
        mount_profile(svc.name, node.name, mnt, rootfs, node.mount)

    cgroup_path = _setup_cgroup(container_name, run.resources)

    # Register cleanup handler for mounts
    register_cleanup(_unmount_fs, rootfs)

    # AppArmor profile generation + loading (optional, Phase 2)
    aa_exec_cmd = None
    security_preset = svc.run.security_preset
    if security_preset:
        try:
            from lib.apparmor.spec import SecuritySpec
            from lib.apparmor.generator import generate_profile
            from lib.apparmor.manager import AppArmorManager

            project_name = svc.meta.get("name", "seed") if svc.meta else "seed"

            # Create SecuritySpec from blueprint
            spec = SecuritySpec.from_blueprint(svc, rootfs, preset=security_preset)

            # Generate profile
            profile_text = generate_profile(spec, svc.name, project_name)

            # Load if AppArmor available
            manager = AppArmorManager()
            if manager.load_profile(profile_text, svc.name, project_name):
                # Get aa-exec wrapper (enforces profile at execution)
                aa_exec_cmd = manager.get_aa_exec_cmd(svc.name, project_name)
                if aa_exec_cmd:
                    emit("info", f"AppArmor profile enforced via aa-exec")
            elif manager.available:
                emit("warn", f"AppArmor load failed for {svc.name} (will continue unconfined)")
            # else: AppArmor not available, continue silently (no error)

        except Exception as e:
            emit("warn", f"AppArmor skipped: {e}")
            # Continue execution normally (graceful fallback)

    # Build sd-init command (replaces unshare + chroot + shell init script)
    cmd = _build_sd_init_cmd(rootfs, container_name, run, cgroup_path)

    # Wrap with aa-exec if AppArmor profile loaded
    if aa_exec_cmd:
        cmd = aa_exec_cmd + cmd

    log_path = os.path.join(container_path, "output.log")
    log_file = open(log_path, "w")
    proc = subprocess.Popen(cmd, stdout=log_file, stderr=log_file,
                            start_new_session=True, close_fds=True, pass_fds=())
    track(proc.pid, container_name, kind="container")

    # Monitor for immediate seccomp violations (exit code 159 = killed by signal 31 SIGSYS)
    import time
    import re
    try:
        proc.wait(timeout=0.5)  # Check if process died immediately
        exit_code = proc.returncode
        log_file.close()
        # Signal 31 (SIGSYS) = seccomp kill. Exit code 128 + 31 = 159
        if exit_code == 159 or exit_code == -31:
            with open(log_path, "r") as f:
                log_content = f.read()

            # Try to extract syscall number from [SECCOMP] message
            syscall_num = None
            syscall_name = None
            match = re.search(r'\[SECCOMP\] Blocked syscall: (\d+)', log_content)
            if match:
                syscall_num = int(match.group(1))
                syscall_name = get_syscall_name(syscall_num)

            # Build error message with syscall info if available
            if syscall_num:
                arch = get_current_arch()
                msg_lines = [
                    f"Container '{container_name}' killed by seccomp (signal 31 SIGSYS)",
                    f"Blocked syscall: {syscall_name}",
                    f"Architecture: {arch}",
                ]

                # Warn if syscall name is unknown (kernel may have newer syscalls)
                if syscall_name.startswith("unknown("):
                    msg_lines.append(f"⚠ Syscall {syscall_num} unknown in {arch} mapping (kernel may have newer syscalls)")
                    msg_lines.append(f"Check kernel sources or: grep -w {syscall_num} /usr/include/asm-*/unistd.h")
                else:
                    # Known syscall: suggest adding it
                    msg_lines.append(f"Add '{syscall_name}' to lib/seccomp/profile.py:ALLOWED_SYSCALLS,")
                    msg_lines.append(f"then run: python3 helpers/gen-seccomp.py && sudo ./install.sh --enable-root")

                error("SECCOMP_VIOLATION", *msg_lines)
            else:
                error("SECCOMP_VIOLATION",
                      f"Container '{container_name}' killed by seccomp (signal 31 SIGSYS)",
                      f"A syscall was blocked by strict allowlist seccomp filter.",
                      f"Check {log_path} for details.",
                      f"Add the missing syscall to lib/seccomp/profile.py:ALLOWED_SYSCALLS,",
                      f"then run: python3 helpers/gen-seccomp.py && make -C helpers sd-init")
    except subprocess.TimeoutExpired:
        pass  # Process still running, proceed normally

    container_ip = ""
    if run.isolation.get("network", True):
        # Direct namespace entry using nsenter with PID (no pgrep race)
        import time
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline:
            try:
                # Use nsenter to detect container's actual namespace PID
                result = subprocess.run(
                    ["sudo", "nsenter", "-t", str(proc.pid), "--all", "--",
                     "sh", "-c", "echo $$"],
                    capture_output=True, text=True, timeout=0.5, close_fds=True
                )
                if result.returncode == 0:
                    break
            except Exception:
                pass
            time.sleep(0.01)
        container_ip = _setup_network(mnt, container_name, svc, rootfs, proc.pid)

    _write_meta(container_path, {
        "name":    container_name,
        "service": svc.name,
        "status":  "running",
        "layer":   layer_id,
        "created": datetime.datetime.now().isoformat(),
        "pid":     str(proc.pid),
        "cgroup":  cgroup_path or "",
        "ip":      container_ip,
        "port":    str(run.port) if run.port else "",
    })

    emit("action", "started", container_name,
         f"ip: {container_ip}" if container_ip else "")
    return proc.pid


def run(svc, mnt: str, container_name: str = None) -> int:
    from common.errors import error

    existing_path, existing_status = _find_existing(mnt, svc.name)

    if existing_status == "running":
        error("ALREADY_RUNNING", f"container for '{svc.name}' is already running",
              "use sd stop <name> first")

    if existing_path and existing_status == "stopped":
        name   = os.path.basename(existing_path)
        rootfs = os.path.join(existing_path, "rootfs")
        emit("log", f"reusing stopped container → {name}")
        emit("action", "restarting", name)
        existing_meta = _read_meta(existing_path)
        layer_id = existing_meta.get("layer", "")
        layer_path = os.path.join(mnt, DIR_LAYERS, layer_id) if layer_id else ""
        return _start_container(existing_path, rootfs, svc, mnt, name,
                                layer_id=layer_id, layer_path=layer_path)

    if not container_name:
        ts             = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
        container_name = f"{svc.name}-{ts}"

    container_path = os.path.join(mnt, DIR_CONTAINERS, container_name)
    rootfs         = os.path.join(container_path, "rootfs")
    os.makedirs(container_path, exist_ok=True)

    emit("action", "building", svc.name)
    app_layer = build(svc, mnt)

    try:
        emit("action", "snapshotting", container_name)
        _snapshot_subvol(app_layer, rootfs)
        increment_refs(app_layer)

        _write_meta(container_path, {
            "name":    container_name,
            "service": svc.name,
            "status":  "starting",
            "layer":   os.path.basename(app_layer),
            "created": datetime.datetime.now().isoformat(),
            "pid":     "",
            "cgroup":  "",
            "ip":      "",
        })

        pid = _start_container(container_path, rootfs, svc, mnt, container_name,
                               layer_id=os.path.basename(app_layer), layer_path=app_layer)

        # Fresh start after first build: stop and restart so proxy reconnects cleanly
        # (service may still be initializing on first run)
        import time
        from engine.container.stop import stop
        time.sleep(1)
        stop(container_name, mnt)
        time.sleep(0.5)
        # Reuse the stopped container (will go through _start_container again)
        return run(svc, mnt, container_name=container_name)
    except Exception as e:
        emit("log", f"build/snapshot failed: {e}, cleaning up")
        try:
            import shutil
            shutil.rmtree(container_path, ignore_errors=True)
        except Exception:
            pass
        raise