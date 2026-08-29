#!/usr/bin/env python3

from __future__ import annotations
import sys
import os
import json
import subprocess
import shutil
import hashlib
import time
import re
import secrets
from pathlib import Path
import signal
import urllib.request
import stat
from typing import Literal
import io
from contextlib import redirect_stdout
from types import SimpleNamespace
import random

# =======================
# DEFINITIONS
# =======================

_STARTUP_STDOUT = io.StringIO()
CFG = SimpleNamespace()

_ORIGINAL_PRINT = print
_ORIGINAL_STDOUT_WRITE = sys.stdout.write
_ORIGINAL_STDERR_WRITE = sys.stderr.write
_INTERACTIVE_MODE_ACTIVE = False
_ANIMATION_LINE_COUNTER = 0

# =======================
# REQUIREMENTS HANDLER
# =======================

def pypi_latest_version(pkg: str) -> str:
    api = f"https://pypi.org/pypi/{pkg}/json"
    with urllib.request.urlopen(api) as r:
        data = json.load(r)
    return data["info"]["version"]

def pypi_wheel_url(pkg: str, version: str) -> str:
    api = f"https://pypi.org/pypi/{pkg}/json"
    with urllib.request.urlopen(api) as r:
        data = json.load(r)

    for f in data["releases"].get(version, []):
        if f["filename"].endswith(".whl"):
            return f["url"]

    raise RuntimeError(f"No wheel found for {pkg}=={version}")

# =======================
# SIGINT HANDLER
# =======================

def _sigint_handler(signum, frame):
    print()
    sys.exit(0)

signal.signal(signal.SIGINT, _sigint_handler)

# =======================
# CONFIG
# =======================

BASE = Path(__file__).resolve().parent
DATA = BASE / "data"
TEMP = DATA / "temp"

CONFIG_DIR = DATA / "database" / "configuration"
CONFIG_FILE = CONFIG_DIR / "config.txt"

SCRAPED = DATA / "scraped"
DB = DATA / "database"
JSON_DB = DB / "scrapedJson"
SHA_DIR = DB / "sha256"
SHA_INDEX = SHA_DIR / "index.json"
VID_INDEX = SHA_DIR / "video_id.json"

REQ = DATA / "requirements"
PYTHON_DIR = REQ / "python"
PYTHON = PYTHON_DIR / ("python.exe" if os.name == "nt" else "python")

PACKAGES = REQ / "packages"
GALLERYDL_PKG = PACKAGES / "gallerydl"
STREAMLINK_PKG = PACKAGES / "streamlink"
CURLCFFI_PKG = PACKAGES / "curlcffi"
YTDLP_PKG = PACKAGES / "ytdlp"

BIN = REQ / "bin"
WHL = REQ / "whl"
INSTALLED = REQ / "installed"
REQ_META = REQ / "meta.json"

LOGS_DIR = DB / "logs"
GENERAL_LOG = LOGS_DIR / "general.log"
DOWNLOADS_LOG = LOGS_DIR / "downloads.csv"
DEBUG_LOG = LOGS_DIR / "debug.log"
DOWNLOAD = DATA / "downloads"

USE_DEFAULT_DOWNLOAD_DIR = False
DOWNLOAD_DIR = ""

QUEUE_UPDATE_DB_ONCE = True
JSON_ID_BYTES = 16

DETAILLED_STARTUP_LOG = True
LOGO_IS_ABOVE_LOG = True

BIN = DATA / "requirements" / "bin"
YTDLP = BIN / ("yt-dlp.exe" if os.name == "nt" else "yt-dlp")
DEBUG_LOG_MAX_BYTES = 10 * 1024 * 1024
LIVE_CACHE: dict[str, bool] = {}
YTDLP_META_CACHE: dict[str, dict] = {}

# Host server state
HOST_PORT = 2211
STARTUP_HOST = "offline"
HOST_ATTACHED = True
MEDIA_PREVIEW_MODE = "thumbnail"
MEDIA_PREVIEW_SEEK_SEC = 5
HOST_SERVER_PROCESS = None
HOST_PID_FILE = None

CONFIG_LAYOUT = [
    ("# Export destination for 'download <hash>' (empty = OS Downloads folder)", None),
    ("EXPORT_DIR", ""),
    ("LIST_NAME_MAX_CHARS", 30),
    (None, None),
    ("# Scrape download staging area", None),
    ("USE_DEFAULT_DOWNLOAD_DIR", False),
    ("DOWNLOAD_DIR", ""),
    (None, None),
    ("# Logging", None),
    ("DEBUG_LOG_MAX_MB", 10),
    (None, None),
    ("# Queue / database behavior", None),
    ("QUEUE_UPDATE_DB_ONCE", True),
    ("JSON_ID_BYTES", 16),
    (None, None),
    ("# Dependency versions", None),
    ("GALLERYDL_VERSION", "1.31.3"),
    ("STREAMLINK_VERSION", "8.1.0"),
    ("CURLCFFI_VERSION", "0.15.0"),
    (None, None),
    ("# Startup behavior", None),
    ("DETAILLED_STARTUP_LOG", True),
    ("LOGO_IS_ABOVE_LOG", True),
    (None, None),
    ("# Interactive mode line delays (milliseconds)", None),
    ("INTERACTIVE_LINE_DELAY_MIN_MS", 2),
    ("INTERACTIVE_LINE_DELAY_MAX_MS", 8),
    ("EXPONENTIAL_ANIMATION", "decelerate"),
    (None, None),
    ("# Web server configuration", None),
    ("HOST_PORT", 2211),
    ("STARTUP_HOST", "offline"),
    ("HOST_ATTACHED", True),
    ("# Card preview mode: disabled | thumbnail | preview", None),
    ("MEDIA_PREVIEW_MODE", "thumbnail"),
    ("# Seek position in seconds for thumbnail/preview capture", None),
    ("MEDIA_PREVIEW_SEEK_SEC", 5),
    (None, None),
    ("# URL normalization (src:dst pairs, comma-separated, e.g. pornhub.org:pornhub.com)", None),
    ("URL_NORMALIZE", "pornhub.org:pornhub.com,xvideos.org:xvideos.com"),
    (None, None),
    ("# Hashing (files larger than HASH_PARTIAL_THRESHOLD_MB only hash head+tail; 0 = always full)", None),
    ("HASH_PARTIAL_THRESHOLD_MB", 50),
    ("HASH_PARTIAL_SAMPLE_MB", 4),
    ("HASH_WORKERS", 4),
    (None, None),
    ("# Sites to force through yt-dlp even if metadata fetch fails (comma-separated domains)", None),
    ("YTDLP_FORCE_DOMAINS", ""),
    ("# Auto-add a domain to YTDLP_FORCE_DOMAINS after a successful 'try anyway' download, no prompt", None),
    ("AUTO_ADD_FORCE_DOMAINS", True),
    ("# Skip quality/format prompts and use best/mp4, unless explicitly passed on the command line", None),
    ("USE_DEFAULTS", True),
]

CONFIG_DEFAULTS: dict[str, object] = {
    k: v for k, v in CONFIG_LAYOUT if k is not None and not k.startswith("#")
}

CONFIG_SCHEMA: dict[str, object] = dict(CONFIG_DEFAULTS)

# =======================
# CONFIG HELPERS
# =======================

def validate_config_values(raw: dict[str, str]) -> tuple[list[str], dict[str, str]]:
    bad, fixed = [], {}

    for k, default in CONFIG_SCHEMA.items():
        if k not in raw:
            continue

        val = raw[k]

        if isinstance(default, str) and ("/" in default or "\\" in default):
            p = Path(val)
            if not p.is_absolute():
                bad.append(k)
                fixed[k] = str(default)
                continue
            try:
                p.parent.mkdir(parents=True, exist_ok=True)
            except Exception:
                bad.append(k)
                fixed[k] = str(default)

    return bad, fixed

def _str_to_bool(s: str) -> bool:
    v = s.strip().lower()
    if v in ("1", "true", "yes", "on"):
        return True
    if v in ("0", "false", "no", "off"):
        return False
    raise ValueError(f"Invalid boolean value: {s!r}")

def _cast_value_by_default(key: str, raw: str):
    if key not in CONFIG_DEFAULTS:
        return raw
    default = CONFIG_SCHEMA[key]
    t = type(default)
    if t is bool:
        return _str_to_bool(raw)
    if t is int:
        try:
            return int(raw)
        except Exception:
            raise ValueError(f"Invalid int for {key}: {raw!r}")
    return raw

def read_config_file(path: Path) -> dict[str, str]:
    d, seen = {}, set()

    if not path.exists():
        return d

    for lineno, ln in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        raw = ln.strip()

        if not raw or raw.startswith("#"):
            continue

        if "=" not in raw:
            key, val = raw.strip(), ""
        else:
            key, val = raw.split("=", 1)
            key, val = key.strip(), val.strip()

        if key in seen:
            d[f"{key}__DUPLICATE__{lineno}"] = val
        else:
            seen.add(key)
            d[key] = val

    return d

def write_config_file(path: Path, data: dict[str, object], with_comments: bool = True):
    lines = []

    if with_comments:
        for key, default in CONFIG_LAYOUT:
            if key is None:
                lines.append("")
            elif key.startswith("#"):
                lines.append(key)
            else:
                val = data.get(key, default)
                lines.append(f"{key}={val}")
    else:
        for k, v in data.items():
            lines.append(f"{k}={v}")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")

def load_and_apply_config() -> tuple[list[str], list[str], list[str]]:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    if not CONFIG_FILE.exists():
        write_config_file(CONFIG_FILE, CONFIG_DEFAULTS, with_comments=True)

    raw = read_config_file(CONFIG_FILE)
    value_bad, fixed = validate_config_values(raw)

    for k in value_bad:
        raw[k] = fixed[k]

    ok_keys, bad_keys, orphan_keys = [], [], []

    for k, default in CONFIG_SCHEMA.items():
        if k in raw:
            try:
                val = _cast_value_by_default(k, raw[k])

                if isinstance(default, str) and default.startswith(str(DATA)):
                    p = Path(os.path.expanduser(val))
                    if not p.is_absolute():
                        p = (BASE / p).resolve()
                    globals()[k] = p
                elif k == "PYTHON":
                    val = raw[k].strip() if raw[k].strip() else default
                    p = Path(val)
                    if not p.is_absolute():
                        p = (BASE / p).resolve()
                    globals()[k] = p
                else:
                    if isinstance(default, str) and default.startswith("/"):
                        p = Path(val)
                        p = Path(val).expanduser()

                        if not p.is_absolute():
                            raise ValueError(f"{k} must be an absolute path")

                        try:
                            p.resolve(strict=False)
                        except Exception:
                            raise ValueError(f"Invalid path for {k}: {val}")

                        globals()[k] = p
                    else:
                        globals()[k] = val

                    setattr(CFG, k, val)
                    ok_keys.append(k)

            except Exception:
                globals()[k] = default
                bad_keys.append(k)
        else:
            default_value = default
            if isinstance(default_value, str) and default_value.startswith(str(DATA)):
                globals()[k] = Path(default_value)
            else:
                globals()[k] = default_value

    for k in raw.keys():
        if k.startswith("__DUPLICATE__") or k not in CONFIG_SCHEMA:
            orphan_keys.append(k)

    for p in (globals()["PACKAGES"], globals()["GALLERYDL_PKG"], globals()["STREAMLINK_PKG"]):
        Path(p).mkdir(parents=True, exist_ok=True)

    if isinstance(globals().get("BIN"), str):
        globals()["BIN"] = Path(globals()["BIN"])
    if isinstance(globals().get("YTDLP"), str):
        y = globals()["YTDLP"]
        globals()["YTDLP"] = Path(y) if Path(y).is_absolute() else globals()["BIN"] / y

    try:
        globals()["DEBUG_LOG_MAX_BYTES"] = int(globals().get("DEBUG_LOG_MAX_MB", 10)) * 1024 * 1024
    except Exception:
        globals()["DEBUG_LOG_MAX_BYTES"] = 10 * 1024 * 1024

    dd = str(globals().get("DOWNLOAD_DIR", "")).strip()

    if dd:
        p = Path(os.path.expanduser(dd))
        if not p.is_absolute():
            p = (BASE / p).resolve()
        globals()["DOWNLOAD"] = p
    else:
        if globals().get("USE_DEFAULT_DOWNLOAD_DIR"):
            try:
                p = get_os_downloads_dir()
                globals()["DOWNLOAD"] = p if p and p.exists() else DATA / "downloads"
            except Exception:
                globals()["DOWNLOAD"] = DATA / "downloads"
        else:
            globals()["DOWNLOAD"] = DATA / "downloads"

    for k in ("SCRAPED", "DB", "JSON_DB", "SHA_DIR", "SHA_INDEX", "VID_INDEX",
              "LOGS_DIR", "GENERAL_LOG", "DOWNLOADS_LOG", "DEBUG_LOG",
              "WHL", "INSTALLED", "REQ_META", "REQ", "PYTHON_DIR"):
        v = globals().get(k)
        if isinstance(v, str):
            globals()[k] = Path(v)

    globals()["QUEUE_UPDATE_DB_ONCE"] = bool(globals().get("QUEUE_UPDATE_DB_ONCE", True))
    globals()["JSON_ID_BYTES"] = int(globals().get("JSON_ID_BYTES", 16))
    globals()["LIVE_CACHE"] = {}
    globals()["YTDLP_META_CACHE"] = {}

    for k, default in CONFIG_SCHEMA.items():
        if k not in globals():
            globals()[k] = default

    if bad_keys or orphan_keys:
        err("Config has errors — run `scraped config recreate` or restart to auto-repair")

    return ok_keys, bad_keys, orphan_keys

def repair_orphan_and_bad(
    ok_keys: list[str],
    bad_keys: list[str],
    orphan_keys: list[str],
) -> tuple[list[str], list[str], list[str]]:
    raw = read_config_file(CONFIG_FILE)
    modified = False

    for k in bad_keys:
        raw[k] = str(CONFIG_SCHEMA[k])
        modified = True

    for k in orphan_keys:
        raw.pop(k, None)
        modified = True

    if modified:
        canonical = {k: raw.get(k, str(CONFIG_SCHEMA[k])) for k in CONFIG_SCHEMA}
        write_config_file(CONFIG_FILE, canonical, with_comments=True)

    return load_and_apply_config()

def _update_pkg(pkg: str, force: bool = False):
    if pkg == "gallerydl":
        old = run_cmd_get_output([get_python(), "-c", f"import sys;sys.path.insert(0,'{GALLERYDL_PKG}');import gallery_dl;print(gallery_dl.__version__)"])
        latest = pypi_latest_version("gallery-dl")
        if old == latest and not force:
            ok(f"gallery-dl already up to date ({latest})")
        else:
            globals()["GALLERYDL_VERSION"] = latest
            _update_config_key("GALLERYDL_VERSION", latest)
            install_gallerydl(force=True)
            ok(f"gallery-dl updated {old} → {latest}" if old != latest else f"gallery-dl reinstalled ({latest})")
    elif pkg == "streamlink":
        old = run_cmd_get_output([get_python(), "-c", f"import sys;sys.path.insert(0,'{STREAMLINK_PKG}');import streamlink;print(streamlink.__version__)"])
        latest = pypi_latest_version("streamlink")
        if old == latest and not force:
            ok(f"streamlink already up to date ({latest})")
        else:
            globals()["STREAMLINK_VERSION"] = latest
            _update_config_key("STREAMLINK_VERSION", latest)
            install_streamlink(force=True)
            ok(f"streamlink updated {old} → {latest}" if old != latest else f"streamlink reinstalled ({latest})")
    elif pkg == "curlcffi":
        old = run_cmd_get_output([get_python(), "-c", f"import sys;sys.path.insert(0,'{CURLCFFI_PKG}');import curl_cffi;print(curl_cffi.__version__)"])
        latest = pypi_latest_version("curl-cffi")
        if old == latest and not force:
            ok(f"curl_cffi already up to date ({latest})")
        else:
            globals()["CURLCFFI_VERSION"] = latest
            _update_config_key("CURLCFFI_VERSION", latest)
            install_curlcffi(force=True)
            ok(f"curl_cffi updated {old} → {latest}" if old != latest else f"curl_cffi reinstalled ({latest})")

def _update_config_key(key: str, value: str):
    raw = read_config_file(CONFIG_FILE)
    raw[key] = value
    canonical = {k: raw.get(k, str(CONFIG_SCHEMA[k])) for k in CONFIG_SCHEMA}
    write_config_file(CONFIG_FILE, canonical, with_comments=True)

def open_config_in_editor():
    editor = os.environ.get("EDITOR") or os.environ.get("VISUAL")
    if editor:
        cmd = [editor, str(CONFIG_FILE)]
    else:
        if os.name == "nt":
            cmd = ["notepad.exe", str(CONFIG_FILE)]
        elif sys.platform == "darwin":
            cmd = ["open", "-a", "TextEdit", str(CONFIG_FILE)]
        else:
            for ed in ("nano", "vi"):
                if shutil.which(ed):
                    cmd = [ed, str(CONFIG_FILE)]
                    break
            else:
                raise RuntimeError("No editor found. Set $EDITOR or install 'nano'/'vi'.")
    subprocess.run(cmd, check=False)

def run_config_command():
    sub = SUB.lower() if isinstance(SUB, str) else ""
    if sub in ("", "check"):
        print(f"Config file: {CONFIG_FILE}")

        ok_keys, bad_keys, orphan_keys = load_and_apply_config()

        for k in CONFIG_DEFAULTS:
            if k in bad_keys:
                print(f"\033[1;31mBAD  {k}\033[0m")
            else:
                print(f"\033[1;32mOK   {k}\033[0m")
        if orphan_keys:
            print("\nOrphan / unknown keys found:")
            for k in orphan_keys:
                print(f"\033[1;33mORPH {k}\033[0m")

        if bad_keys or orphan_keys:
            changed = repair_orphan_and_bad(ok_keys, bad_keys, orphan_keys)
            if changed:
                ok('Config file repaired automatically — re-run "config check" to verify')
            return

        return

    if sub == "recreate":
        write_config_file(CONFIG_FILE, CONFIG_SCHEMA, with_comments=True)
        ok("Config recreated from defaults")
        return

    if sub == "reload":
        if hasattr(sys, "_orig_argv"):
            err("config reload is only available in interactive mode")
            return

        ok("Reloading configuration (restarting UI)")
        sys.exit(0)

    if sub == "edit":
        try:
            open_config_in_editor()
            ok("Editor closed")
        except Exception as e:
            err(f"Failed to open editor: {e}")
        return

    err("Invalid config subcommand (check | recreate | edit)")

# =======================
# FILE LOGGING
# =======================

def log_file(msg: str):
    ts_full = _now_full()
    pid, cwd = os.getpid(), os.getcwd()
    with open(GENERAL_LOG, "a", encoding="utf-8") as f:
        f.write(f"[{ts_full}] PID={pid} CWD={cwd} | {msg}\n")

def _now_full() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")

def rotate_debug_log():
    if DEBUG_LOG.exists() and DEBUG_LOG.stat().st_size > DEBUG_LOG_MAX_BYTES:
        DEBUG_LOG.write_text(f"[{_now_full()}] DEBUG LOG ROTATED\n")

def log_debug(msg: str):
    rotate_debug_log()
    with open(DEBUG_LOG, "a", encoding="utf-8") as f:
        f.write(f"[{_now_full()}] {msg}\n")

def log_download(method: str, url: str, path: Path):
    ts_full = _now_full()
    size = path.stat().st_size if path.exists() else 0
    with open(DOWNLOADS_LOG, "a", encoding="utf-8") as f:
        f.write(f"{ts_full}|{method}|{url}|{path}|{size}\n")

# =======================
# GLOBAL STATE
# =======================

URLS: list[str] = []
VIDEO_ID_CACHE: dict[str, str] = {}

# =======================
# INIT (two-phase)
# =======================

for p in (DATA, TEMP):
    p.mkdir(parents=True, exist_ok=True)

CONFIG_DIR.mkdir(parents=True, exist_ok=True)

with redirect_stdout(_STARTUP_STDOUT):
    for p in (DATA, TEMP):
        p.mkdir(parents=True, exist_ok=True)

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    for p in (
        DATA, TEMP, DOWNLOAD, SCRAPED, DB, JSON_DB, SHA_DIR, REQ,
        Path(globals().get("PYTHON_DIR", REQ / "python")),
        Path(globals().get("BIN", REQ / "bin")),
    ):
        Path(p).mkdir(parents=True, exist_ok=True)

    for idx_file in (SHA_INDEX, VID_INDEX):
        if not idx_file.exists():
            idx_file.write_text("{}")

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    for lf in (GENERAL_LOG, DOWNLOADS_LOG, DEBUG_LOG):
        Path(lf).touch(exist_ok=True)

    if DOWNLOADS_LOG.stat().st_size == 0:
        DOWNLOADS_LOG.write_text("timestamp|method|url|final_path|size_bytes\n", encoding="utf-8")

    # Initialize host PID file path
    globals()["HOST_PID_FILE"] = DATA / "host_server.pid"

# =======================
# LOGGING
# =======================

def ts() -> str:
    return time.strftime("[%H:%M:%S]")

# =======================
# SPINNER & PROGRESS
# =======================

class Spinner:
    """Animated spinner for long operations"""
    def __init__(self, message: str = "Processing"):
        self.message = message
        self.frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        self.idx = 0
        self.running = False
        self._thread = None

    def _spin(self):
        while self.running:
            sys.stderr.write(f"\r{self.frames[self.idx]} {self.message}...")
            sys.stderr.flush()
            self.idx = (self.idx + 1) % len(self.frames)
            time.sleep(0.1)

    def start(self):
        self.running = True
        import threading
        self._thread = threading.Thread(target=self._spin, daemon=True)
        self._thread.start()

    def stop(self, final_message: str = None):
        self.running = False
        if self._thread:
            self._thread.join(timeout=0.5)
        sys.stderr.write("\r" + " " * (len(self.message) + 10) + "\r")
        sys.stderr.flush()
        if final_message:
            ok(final_message)

def progress_bar(current: int, total: int, prefix: str = "", width: int = 40) -> str:
    """Generate a progress bar string"""
    if total == 0:
        percent = 100
    else:
        percent = int((current / total) * 100)

    filled = int((current / total) * width) if total > 0 else width
    bar = "█" * filled + "░" * (width - filled)

    return f"{prefix} |{bar}| {percent}% ({current}/{total})"

# =======================
# INTERACTIVE MODE LINE DELAY SYSTEM
# =======================

def _get_validated_delays() -> tuple[int, int] | None:
    min_delay = globals().get("INTERACTIVE_LINE_DELAY_MIN_MS", 50)
    max_delay = globals().get("INTERACTIVE_LINE_DELAY_MAX_MS", 750)

    if (isinstance(min_delay, int) and isinstance(max_delay, int) and
        0 < min_delay < 10000 and 0 < max_delay < 10000 and max_delay > min_delay):
        return (min_delay, max_delay)
    return None

def _calculate_delay_with_curve(min_ms: int, max_ms: int) -> float:
    global _ANIMATION_LINE_COUNTER
    _ANIMATION_LINE_COUNTER += 1

    mode = str(globals().get("EXPONENTIAL_ANIMATION", "none")).strip().lower()

    if mode == "none":
        return random.randint(min_ms, max_ms) / 1000.0

    curve_strength = 4.0
    progress = min(_ANIMATION_LINE_COUNTER / 50.0, 1.0)

    if mode == "decelerate":
        weight = (1.0 - progress) ** curve_strength
        biased_midpoint = min_ms + (max_ms - min_ms) * weight
        range_width = (max_ms - min_ms) * 0.3
        range_min = max(min_ms, biased_midpoint - range_width / 2)
        range_max = min(max_ms, biased_midpoint + range_width / 2)
        return random.uniform(range_min, range_max) / 1000.0

    elif mode == "accelerate":
        weight = progress ** curve_strength
        biased_midpoint = min_ms + (max_ms - min_ms) * weight
        range_width = (max_ms - min_ms) * 0.3
        range_min = max(min_ms, biased_midpoint - range_width / 2)
        range_max = min(max_ms, biased_midpoint + range_width / 2)
        return random.uniform(range_min, range_max) / 1000.0

    return random.randint(min_ms, max_ms) / 1000.0

def _delayed_print(*args, **kwargs):
    _ORIGINAL_PRINT(*args, **kwargs)
    if _INTERACTIVE_MODE_ACTIVE:
        delays = _get_validated_delays()
        if delays:
            time.sleep(_calculate_delay_with_curve(*delays))

def _delayed_stdout_write(text):
    result = _ORIGINAL_STDOUT_WRITE(text)
    if _INTERACTIVE_MODE_ACTIVE and '\n' in text:
        delays = _get_validated_delays()
        if delays:
            time.sleep(_calculate_delay_with_curve(*delays))
    return result

def _delayed_stderr_write(text):
    result = _ORIGINAL_STDERR_WRITE(text)
    if _INTERACTIVE_MODE_ACTIVE and '\n' in text:
        delays = _get_validated_delays()
        if delays:
            time.sleep(_calculate_delay_with_curve(*delays))
    return result

def enable_interactive_delays():
    global _INTERACTIVE_MODE_ACTIVE, _ANIMATION_LINE_COUNTER
    _INTERACTIVE_MODE_ACTIVE = True
    _ANIMATION_LINE_COUNTER = 0

    import builtins
    builtins.print = _delayed_print
    sys.stdout.write = _delayed_stdout_write
    sys.stderr.write = _delayed_stderr_write

def disable_interactive_delays():
    global _INTERACTIVE_MODE_ACTIVE
    _INTERACTIVE_MODE_ACTIVE = False

    import builtins
    builtins.print = _ORIGINAL_PRINT
    sys.stdout.write = _ORIGINAL_STDOUT_WRITE
    sys.stderr.write = _ORIGINAL_STDERR_WRITE

def _emit(line: str):
    if DETAILLED_STARTUP_LOG and LOGO_IS_ABOVE_LOG:
        _STARTUP_STDOUT.write(line + "\n")
    else:
        print(line)

def log(msg: str) -> None:
    out = f"{ts()} INFO  {msg}"
    _emit(f"\033[1;34m{out}\033[0m")
    log_file(f"INFO  {msg}")
    log_debug(out)

def ok(msg: str) -> None:
    out = f"{ts()} OK    {msg}"
    _emit(f"\033[1;32m{out}\033[0m")
    log_file(f"OK    {msg}")
    log_debug(out)

def warn(msg: str) -> None:
    out = f"{ts()} WARN  {msg}"
    _emit(f"\033[1;33m{out}\033[0m")
    log_file(f"WARN  {msg}")
    log_debug(out)

def err(msg: str) -> None:
    out = f"{ts()} ERR   {msg}"
    _emit(f"\033[1;31m{out}\033[0m")
    log_file(f"ERR   {msg}")
    log_debug(out)

def startup_report(interactive: bool):
    ok("Initialization started")
    print(f"\033[0;36m┌─ System Information\033[0m")
    print(f"\033[0;36m├─\033[0m Script: {BASE}")
    print(f"\033[0;36m├─\033[0m Config: {CONFIG_FILE}")
    print(f"\033[0;36m├─\033[0m Data: {DATA}")
    print(f"\033[0;36m├─\033[0m Downloads: {DOWNLOAD}")
    print(f"\033[0;36m├─\033[0m OS: {os.name} | Python: {sys.version.split()[0]}")
    print(f"\033[0;36m├─\033[0m Mode: {'Interactive' if interactive else 'CLI'}")

    try:
        usage = shutil.disk_usage(DOWNLOAD)
        free_gb = usage.free / (1024 ** 3)
        print(f"\033[0;36m├─\033[0m Free Space: {free_gb:.2f} GB")
    except Exception:
        print(f"\033[0;36m├─\033[0m Free Space: Unknown")

    print(f"\033[0;36m├─ Tools\033[0m")
    print(f"\033[0;36m├─\033[0m yt-dlp: {YTDLP}")
    print(f"\033[0;36m├─\033[0m gallery-dl: v{GALLERYDL_VERSION}")
    print(f"\033[0;36m└─\033[0m streamlink: v{STREAMLINK_VERSION}")
    ok("Initialization complete")

_CONFIG_RESULT = load_and_apply_config()

# =======================
# DEPENDENCY BOOTSTRAP
# =======================

WHL.mkdir(parents=True, exist_ok=True)
INSTALLED.mkdir(parents=True, exist_ok=True)

def ensure_binary(path: Path, url: str) -> None:
    if path.exists():
        return

    log(f"Downloading {path.name}...")
    path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, path)
    log_debug(f"Downloaded binary {path.name} from {url}")

    if os.name != "nt":
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    ok(f"{path.name} ready")

def ensure_embedded_python():
    if os.name != "nt":
        log("Using bundled Python" if PYTHON.exists() else "Using system Python")
        return

    if PYTHON.exists():
        return

    log("Downloading embedded Python...")
    PYTHON_DIR.mkdir(parents=True, exist_ok=True)

    url = "https://www.python.org/ftp/python/3.12.1/python-3.12.1-embed-amd64.zip"
    zip_path = PYTHON_DIR / "python-embed.zip"
    urllib.request.urlretrieve(url, zip_path)

    import zipfile
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(PYTHON_DIR)

    zip_path.unlink()

    pth = PYTHON_DIR / "python312._pth"
    if pth.exists():
        lines = [l for l in pth.read_text().splitlines() if not l.startswith("#")]
        lines.extend(["python312.zip", "."])
        pth.write_text("\n".join(lines))

    ok("Embedded Python ready")

def remove_dep(path: Path):
    if path.exists():
        shutil.rmtree(path, ignore_errors=True)

def get_python() -> str:
    return str(PYTHON) if PYTHON.exists() else sys.executable

def install_gallerydl(force: bool = False):
    if force:
        shutil.rmtree(GALLERYDL_PKG, ignore_errors=True)
        GALLERYDL_PKG.mkdir(parents=True, exist_ok=True)

    if (Path(GALLERYDL_PKG) / "gallery_dl").exists():
        log("gallery-dl already installed")
        return

    import zipfile
    wheel = WHL / f"gallery_dl-{GALLERYDL_VERSION}-py3-none-any.whl"
    ensure_binary(wheel, pypi_wheel_url("gallery-dl", GALLERYDL_VERSION))
    with zipfile.ZipFile(wheel) as z:
        z.extractall(GALLERYDL_PKG)

    ok("gallery-dl installed")

def pypi_platform_wheel_url(pkg: str, version: str) -> str:
    import platform as _platform
    api = f"https://pypi.org/pypi/{pkg}/json"
    with urllib.request.urlopen(api) as r:
        data = json.load(r)

    files = data["releases"].get(version, [])
    machine = _platform.machine().lower()
    is_musl = Path("/etc/alpine-release").exists() or Path("/lib/libc.musl-x86_64.so.1").exists()

    def score(f: dict) -> int:
        n = f["filename"]
        if not n.endswith(".whl"):
            return -1
        if machine == "x86_64":
            if "x86_64" not in n:
                return -1
        elif machine == "aarch64":
            if "aarch64" not in n:
                return -1
        if is_musl and "musl" in n:
            return 2
        if not is_musl and "manylinux" in n:
            return 2
        if "linux" in n:
            return 1
        return -1

    candidates = [(score(f), f) for f in files if score(f) >= 0]
    if not candidates:
        raise RuntimeError(f"No compatible wheel found for {pkg}=={version} on {machine}")
    return max(candidates, key=lambda x: x[0])[1]["url"]

def install_ytdlp_pkg(force: bool = False):
    if force:
        shutil.rmtree(YTDLP_PKG, ignore_errors=True)

    if (YTDLP_PKG / "yt_dlp").exists():
        log("yt-dlp already installed")
        return

    YTDLP_PKG.mkdir(parents=True, exist_ok=True)
    latest = pypi_latest_version("yt-dlp")
    wheel_url = pypi_wheel_url("yt-dlp", latest)
    wheel_name = wheel_url.split("/")[-1]
    wheel = WHL / wheel_name
    log(f"Downloading yt-dlp-{latest}...")
    ensure_binary(wheel, wheel_url)

    import zipfile
    with zipfile.ZipFile(wheel) as z:
        z.extractall(YTDLP_PKG)

    ok(f"yt-dlp {latest} installed")

def install_curlcffi(force: bool = False):
    if force:
        shutil.rmtree(CURLCFFI_PKG, ignore_errors=True)

    if (CURLCFFI_PKG / "curl_cffi").exists():
        log("curl_cffi already installed")
        return

    CURLCFFI_PKG.mkdir(parents=True, exist_ok=True)

    url = pypi_platform_wheel_url("curl-cffi", CURLCFFI_VERSION)
    wheel_name = url.split("/")[-1]
    wheel = WHL / wheel_name

    import zipfile
    if wheel.exists():
        try:
            zipfile.ZipFile(wheel).close()
        except zipfile.BadZipFile:
            wheel.unlink()

    ensure_binary(wheel, url)

    with zipfile.ZipFile(wheel) as z:
        z.extractall(CURLCFFI_PKG)

    ok("curl_cffi installed")

def install_streamlink(force: bool = False):
    if force:
        shutil.rmtree(STREAMLINK_PKG, ignore_errors=True)
        STREAMLINK_PKG.mkdir(parents=True, exist_ok=True)

    if (STREAMLINK_PKG / "streamlink").exists():
        log("streamlink already installed")
        return

    import zipfile
    wheel = WHL / f"streamlink-{STREAMLINK_VERSION}-py3-none-any.whl"
    ensure_binary(wheel, pypi_wheel_url("streamlink", STREAMLINK_VERSION))
    with zipfile.ZipFile(wheel) as z:
        z.extractall(STREAMLINK_PKG)

    ok("streamlink installed")

def current_platform_id() -> str:
    if os.name == "nt":
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    return "linux"

def requirements_match_platform() -> bool:
    try:
        meta = json.load(open(REQ_META))
        return meta.get("platform") == current_platform_id()
    except Exception:
        return False

def ensure_dependencies():
    ensure_embedded_python()

    install_ytdlp_pkg()
    install_gallerydl()
    install_streamlink()

    REQ_META.write_text(json.dumps({"platform": current_platform_id()}, indent=2))

def _pkg_dirs() -> list[str]:
    return [str(YTDLP_PKG), str(CURLCFFI_PKG), str(GALLERYDL_PKG), str(STREAMLINK_PKG)]

def _ytdlp_cmd(args: list[str]) -> list[str]:
    dirs = ":".join(_pkg_dirs())
    return [
        get_python(), "-c",
        f"import sys; [sys.path.insert(0,p) for p in '{dirs}'.split(':')]; from yt_dlp import main; main()",
        *args,
    ]

def wipe_requirements():
    if REQ.exists():
        shutil.rmtree(REQ, ignore_errors=True)
    REQ.mkdir(parents=True, exist_ok=True)

if REQ.exists() and not requirements_match_platform():
    warn("Requirements built for different OS — rebuilding")
    wipe_requirements()

if len(sys.argv) > 1 and sys.argv[1] in ("remove", "list", "log", "config"):
    log_debug("Skipping dependency bootstrap for read-only command")
else:
    ensure_dependencies()

# =======================
# USAGE
# =======================

def usage() -> None:
    sections = [
        ("📥 DOWNLOAD", [
            "  download <hash> [path]             Copy file from DB to export dir (or path)",
            "  scrape <url> [quality] [fmt]       Database-tracked scrape",
            "  queue                              Interactive queue mode",
        ]),
        ("🗄️  DATABASE", [
            "  list                               List database entries",
            "  remove <sha|prefix>                Remove media by hash or prefix",
            "  remove logs [file] [lines]         Truncate log files",
        ]),
        ("🔄 UPDATES", [
            "  update | update all                Update all dependencies (if outdated)",
            "  update force                       Force reinstall all dependencies",
            "  update ytdl                        Update yt-dlp only",
            "  update gallerydl                   Reinstall gallery-dl",
            "  update streamlink                  Reinstall streamlink",
            "  update curlcffi                    Reinstall curl_cffi (browser impersonation)",
            "  update database                    Rebuild database",
            "  update json [len]                  Rename JSON files",
        ]),
        ("🌐 WEB SERVER", [
            "  host status                        Show current server status",
            "  host public                        Start server (network-accessible)",
            "  host private                       Start server (localhost-only)",
            "  host offline                       Stop server",
            "  host detach                        Run server in background",
            "  host attach                        Bind server back to TUI",
            "  host kill                          Force-kill all server processes",
        ]),
        ("🛠️  MAINTENANCE", [
            "  uninstall                          Remove all data",
            "  log [file] [lines]                 View logs",
            "  supported [site]                   List or check yt-dlp supported sites",
        ]),
        ("⚙️  CONFIGURATION", [
            "  config check                       Validate config file and optionally repair",
            "  config recreate                    Recreate config file from defaults",
            "  config edit                        Open config file in editor",
        ]),
    ]

    print("\n\033[1;36m╔════════════════════════════════════════════════════════════════╗\033[0m")
    print("\033[1;36m║                        COMMAND REFERENCE                       ║\033[0m")
    print("\033[1;36m╚════════════════════════════════════════════════════════════════╝\033[0m\n")

    for title, commands in sections:
        print(f"\033[1;33m{title}\033[0m")
        for cmd in commands:
            print(cmd)
        print()

# =======================
# ARG PARSE
# =======================

def parse_args_and_prepare():
    if len(sys.argv) == 1:
        usage()
        sys.exit(0)

    global CMD, SUB
    CMD = sys.argv[1]
    SUB = sys.argv[2] if len(sys.argv) > 2 else ""

    log_file(f"Command invoked: {' '.join(sys.argv)}")
    log_debug(f"Parsed command CMD={CMD} SUB={SUB}")

    if CMD in ("help",):
        usage()
        sys.exit(0)

    if CMD == "uninstall":
        uninstall_all()

    if CMD in ("download", "queue", "list", "remove", "update", "log", "supported", "config", "host"):
        return

    if CMD == "scrape":
        if len(sys.argv) < 3:
            err("Missing URL")
            sys.exit(1)

        URLS.clear()
        url = normalize_url(sys.argv[2])
        quality = container = duration_flag = None

        for arg in sys.argv[3:]:
            a = arg.lower()
            if a in ("best", "high", "medium", "low"):
                quality = a
            elif a in ("mp4", "webm", "mkv"):
                container = a
            else:
                parsed = parse_duration_flag(a)
                if parsed is not None:
                    duration_flag = parsed

        try:
            extractor = detect_extractor(url)
        except Exception:
            extractor = "none"
        quality, container = prompt_for_extractor_params(extractor, quality, container)
        URLS.append(f"{url}|{quality}|{container}|{extractor}|{duration_flag}")
        return

    err("Invalid command")
    usage()
    sys.exit(1)

# =======================
# HELPERS
# =======================

def get_ytdlp_meta(url: str) -> dict | None:
    if url in YTDLP_META_CACHE:
        return YTDLP_META_CACHE[url]

    # --impersonate chrome needs a JS runtime for some extractors; if that probe
    # fails, retry without it — the real download command doesn't use it either,
    # so this keeps detection in sync with what actually works.
    for extra_args in (["--impersonate", "chrome"], []):
        try:
            res = subprocess.run(
                _ytdlp_cmd(["--skip-download", "--no-warnings", "--no-call-home",
                    "--no-update", "--no-check-certificates", "--dump-single-json",
                    "--no-playlist", *extra_args, url]),
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                text=True, timeout=30,
            )

            if res.returncode != 0 or not res.stdout:
                continue

            meta = json.loads(res.stdout)
            YTDLP_META_CACHE[url] = meta
            return meta

        except Exception:
            continue

    return None

def is_live_from_meta(meta: dict | None) -> bool:
    if not meta:
        return False
    return bool(meta.get("is_live") is True or meta.get("live_status") == "is_live")

def run_module(pkg_dir: Path, module: str, args: list[str]):
    cmd = [
        get_python(), "-c",
        f"import sys;sys.path.insert(0, '{pkg_dir}');import {module};{module}.main()",
        *args,
    ]
    subprocess.run(cmd, check=False)

def update_ytdlp():
    old = run_cmd_get_output(_ytdlp_cmd(["--version"]))
    latest = pypi_latest_version("yt-dlp")
    log_debug(f"yt-dlp old={old} latest={latest}")
    if old == latest:
        ok(f"yt-dlp already up to date ({latest})")
        return
    install_ytdlp_pkg(force=True)
    new = run_cmd_get_output(_ytdlp_cmd(["--version"]))
    ok(f"yt-dlp updated {old} → {new}")

def run_update():
    target = SUB
    force = "force" in sys.argv or target == "all"

    if target in ("", "all", "force"):
        if force:
            log("Force update: wiping requirements")
            wipe_requirements()
            ensure_dependencies()
        else:
            update_ytdlp()
            _update_pkg("gallerydl")
            _update_pkg("streamlink")
            _update_pkg("curlcffi")

        run_db_update()
        ok("All components updated")
        return

    if target == "ytdl":
        update_ytdlp()
        return

    if target == "gallerydl":
        _update_pkg("gallerydl", force=force)
        return

    if target == "streamlink":
        _update_pkg("streamlink", force=force)
        return

    if target == "curlcffi":
        _update_pkg("curlcffi", force=force)
        return

    if target == "database":
        run_db_update()
        return

    usage()

def select_format(quality: str) -> str:
    return {
        "best": "bestvideo+bestaudio/best",
        "high": "bv*[height<=1080]/bv*/best",
        "medium": "bv*[height<=720]/bv*/best",
        "low": "bv*[height<=480]/bv*/best",
    }.get(quality, "bestvideo+bestaudio/best")

def select_container(fmt: str) -> str:
    return fmt if fmt in ("mp4", "webm", "mkv") else "mp4"

_HASH_CACHE_FILE = DB / "sha256" / "hash_cache.json"
_HASH_CACHE: dict[str, str] = {}
_HASH_CACHE_DIRTY = False

def _load_hash_cache():
    global _HASH_CACHE
    try:
        _HASH_CACHE = json.loads(_HASH_CACHE_FILE.read_text())
    except Exception:
        _HASH_CACHE = {}

def _save_hash_cache():
    if _HASH_CACHE_DIRTY:
        _HASH_CACHE_FILE.write_text(json.dumps(_HASH_CACHE))

def _hash_cache_key(path: Path) -> str:
    st = path.stat()
    return f"{path}:{st.st_size}:{st.st_mtime}"

def _sha256_file_uncached(path: Path) -> str:
    threshold = int(globals().get("HASH_PARTIAL_THRESHOLD_MB", 50)) * 1024 * 1024
    sample    = int(globals().get("HASH_PARTIAL_SAMPLE_MB", 4))    * 1024 * 1024
    size      = path.stat().st_size

    h = hashlib.sha256()
    h.update(size.to_bytes(8, "little"))  # embed size so partial hashes can't collide across different-sized files

    if threshold > 0 and size > threshold and sample > 0:
        with open(path, "rb") as fh:
            h.update(fh.read(sample))
            if size > sample * 2:
                fh.seek(max(0, size - sample))
                h.update(fh.read(sample))
    else:
        with open(path, "rb") as fh:
            for block in iter(lambda: fh.read(1024 * 1024), b""):
                h.update(block)

    return h.hexdigest()

def sha256_file(path: Path) -> str:
    global _HASH_CACHE_DIRTY
    key = _hash_cache_key(path)
    if key in _HASH_CACHE:
        return _HASH_CACHE[key]
    digest = _sha256_file_uncached(path)
    _HASH_CACHE[key] = digest
    _HASH_CACHE_DIRTY = True
    return digest

def run_cmd_get_output(args: list[str], env: dict = None) -> str:
    res = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=env)
    return res.stdout.strip() if res.returncode == 0 else ""

def get_video_id(url: str) -> str | None:
    meta = get_ytdlp_meta(url)
    return meta.get("id") if meta else None

def get_video_id_for_dedup(url: str) -> str:
    # Forced domains skip metadata fetch (it's usually the reason they're forced),
    # so fall back to a URL-derived key instead of treating "no metadata" as "invalid".
    return get_video_id(url) or f"url:{hashlib.sha256(url.encode()).hexdigest()[:16]}"

def parse_duration_flag(s: str) -> int | None | Literal["manual"]:
    if not s:
        return None

    s = s.lower().strip()
    if s == "manual":
        return "manual"

    if len(s) < 2 or not s[:-1].isdigit():
        return None

    n = int(s[:-1])
    unit = s[-1]

    if unit == "s":
        return n
    if unit == "m":
        return n * 60
    if unit == "h":
        return n * 3600

    return None

def record_live_stream(url: str, quality: str, duration_flag):
    import signal

    title = run_cmd_get_output(_ytdlp_cmd(["--skip-download", "--print", "title", url])) or "Live Stream"
    safe_title = re.sub(r'[\\/:*?"<>|]+', "_", title).strip()
    start_ts = time.strftime("%Y-%m-%d_%H-%M-%S")
    start_time = time.time()

    manual = True
    duration = None

    if isinstance(duration_flag, str) and duration_flag != "manual":
        m = re.fullmatch(r"(\d+)([smh])", duration_flag)
        if m:
            n = int(m.group(1))
            duration = n * {"s": 1, "m": 60, "h": 3600}[m.group(2)]
            manual = False

    fmt = select_format(quality or "best")
    container = select_container("mp4")

    shutil.rmtree(TEMP, ignore_errors=True)
    TEMP.mkdir(parents=True, exist_ok=True)

    out_tmpl = TEMP / f"{safe_title}.%(ext)s"

    cmd = _ytdlp_cmd(["--live-from-start", "--hls-use-mpegts", "--no-part",
        "--no-mtime", "-f", fmt, "--merge-output-format", container,
        "-o", str(out_tmpl), url])

    proc = subprocess.Popen(
        cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid if os.name != "nt" else None,
    )

    aborted = False

    def handle_sigint(signum, frame):
        proc.send_signal(signal.SIGINT)

    def handle_sigquit(signum, frame):
        nonlocal aborted
        aborted = True
        proc.kill()

    signal.signal(signal.SIGINT, handle_sigint)
    signal.signal(signal.SIGQUIT, handle_sigquit)

    print("Stream recording started")
    print("Press Ctrl+C to save, Ctrl+\\ to abort")

    if manual:
        print("Automatically recording until the stream goes offline, is aborted, or is manually saved")
    else:
        print(f"Recording for {duration} seconds")

    last_size = last_time = 0
    last_time = start_time

    while proc.poll() is None:
        now = time.time()
        elapsed = int(now - start_time)

        if not manual and elapsed >= duration:
            proc.send_signal(signal.SIGINT)
            break

        size = sum(p.stat().st_size for p in TEMP.iterdir() if p.is_file())
        delta = size - last_size
        speed = (delta / max(now - last_time, 1)) / (1024 * 1024)

        last_size, last_time = size, now
        mm, ss = divmod(elapsed, 60)

        if manual:
            line = f"{safe_title} | {mm:02}:{ss:02} | {speed:.2f} MB/s"
        else:
            remaining = max(duration - elapsed, 0)
            rm, rs = divmod(remaining, 60)
            line = f"{safe_title} | {mm:02}:{ss:02} | {speed:.2f} MB/s | remaining {rm:02}:{rs:02}"

        sys.stderr.write("\r" + line + " " * 10)
        sys.stderr.flush()
        time.sleep(1)

    sys.stderr.write("\n")
    sys.stderr.flush()

    if aborted:
        proc.kill()
        shutil.rmtree(TEMP, ignore_errors=True)
        TEMP.mkdir(exist_ok=True)
        warn("Recording aborted")
        return

    files = [p for p in TEMP.iterdir() if p.is_file() and not p.name.endswith(".part") and "-Frag" not in p.name]

    if not files:
        warn("No finalized live stream file found")
        return

    media = max(files, key=lambda p: p.stat().st_mtime)
    end_ts = time.strftime("%Y-%m-%d_%H-%M-%S")
    final_name = f"{safe_title} - [{start_ts} - {end_ts}].{container}"
    media_dest = SCRAPED / final_name
    media.rename(media_dest)

    h = sha256_file(media_dest)

    json.dump({
        "url": url, "title": title, "live": True,
        "duration": int(time.time() - start_time), "media_sha256": h,
    }, open(JSON_DB / f"{secrets.token_hex(JSON_ID_BYTES)}.json", "w"), indent=2)

    index = json.load(open(SHA_INDEX))
    index[h] = str(media_dest)
    json.dump(index, open(SHA_INDEX, "w"), indent=2)

    shutil.rmtree(TEMP, ignore_errors=True)
    TEMP.mkdir(exist_ok=True)

    ok(f"Saved live stream {media_dest.name}")

def load_video_index() -> None:
    try:
        VIDEO_ID_CACHE.update(json.load(open(VID_INDEX)))
    except Exception:
        pass

def video_id_exists(vid: str) -> bool:
    h = VIDEO_ID_CACHE.get(vid)
    if not h:
        return False

    try:
        index = json.load(open(SHA_INDEX))
        p = index.get(h)
        return p and Path(p).exists()
    except Exception:
        return False

def get_os_downloads_dir() -> Path:
    try:
        if os.name == "nt":
            return Path(os.environ["USERPROFILE"]) / "Downloads"
        else:
            return Path.home() / "Downloads"
    except Exception:
        return BASE

def reset_download_dir():
    shutil.rmtree(DOWNLOAD, ignore_errors=True)
    DOWNLOAD.mkdir(exist_ok=True)

def get_export_dir() -> Path:
    d = str(globals().get("EXPORT_DIR", "")).strip()
    if d:
        p = Path(os.path.expanduser(d))
        return p if p.is_absolute() else (BASE / p).resolve()
    return get_os_downloads_dir()

def export_by_hash(prefix: str, dest: Path | None = None):
    try:
        index = json.load(open(SHA_INDEX))
    except Exception:
        err("SHA index unreadable")
        return

    matches = [h for h in index if h.lower().startswith(prefix.lower())]

    if not matches:
        warn(f"No entry matching '{prefix}'")
        return

    if len(matches) > 1:
        warn("Ambiguous prefix — be more specific:")
        for h in matches:
            print(f"  {h[:16]}")
        return

    h = matches[0]
    src = Path(index[h])

    if not src.exists():
        err(f"File missing from disk: {src.name} — run 'update database'")
        return

    out_dir = dest if dest else get_export_dir()
    out_dir.mkdir(parents=True, exist_ok=True)
    dst = out_dir / src.name

    shutil.copy2(src, dst)
    ok(f"Copied to {dst}")

def prompt_for_extractor_params(
    extractor: Extractor,
    quality: str | None,
    container: str | None,
) -> tuple[str | None, str | None]:
    if extractor == "yt-dlp":
        return prompt_missing_params(quality, container)

    if extractor == "streamlink":
        if quality is None:
            if _INTERACTIVE_MODE_ACTIVE and not bool(globals().get("USE_DEFAULTS", True)):
                q = safe_input("Select stream quality [best/worst/720p/480p] [best]: ").strip().lower()
                quality = q if q else "best"
            else:
                quality = "best"
        return quality, None

    return None, None

def prompt_missing_params(
    quality: str | None,
    container: str | None,
) -> tuple[str, str]:
    qualities = ["best", "high", "medium", "low"]
    formats = ["mp4", "webm", "mkv"]
    prompt_allowed = _INTERACTIVE_MODE_ACTIVE and not bool(globals().get("USE_DEFAULTS", True))

    if quality is None:
        if prompt_allowed:
            q = safe_input(f"Select quality {qualities} [best]: ").strip().lower()
            quality = q if q in qualities else "best"
        else:
            quality = "best"

    if container is None:
        if prompt_allowed:
            f = safe_input(f"Select format {formats} [mp4]: ").strip().lower()
            container = f if f in formats else "mp4"
        else:
            container = "mp4"

    return quality, container

def safe_input(prompt: str = "") -> str:
    try:
        return input(prompt)
    except UnicodeDecodeError:
        warn("Invalid input encoding ignored")
        return ""

def list_supported():
    print("\nyt-dlp [videos] supports:")
    print(run_cmd_get_output(_ytdlp_cmd(["--list-extractors"])))

    print("\ngallery-dl [images] supports:")
    subprocess.run([
        get_python(), "-c",
        f"import sys;sys.path.insert(0, '{GALLERYDL_PKG}');import gallery_dl;gallery_dl.main()",
        "--list-extractors",
    ])

    print("\nstreamlink [live streams] supports:")
    subprocess.run([
        get_python(), "-c",
        f"import sys;sys.path.insert(0, '{STREAMLINK_PKG}');import streamlink;streamlink.main()",
        "--plugins",
    ])

def check_supported(site: str):
    if supports_ytdlp(site):
        subprocess.run(_ytdlp_cmd(["--list-extractors"]), check=False)
        return

    if supports_streamlink(site):
        run_module(STREAMLINK_PKG, "streamlink", ["--plugins"])
        return

    if supports_gallerydl(site):
        run_module(GALLERYDL_PKG, "gallery_dl", ["--list-extractors"])
        return

    warn("Site not supported by any extractor")

# =======================
# EXTRACTOR
# =======================

Extractor = Literal["yt-dlp", "gallery-dl", "streamlink", "none"]

def supports_ytdlp(url: str) -> bool:
    return get_ytdlp_meta(url) is not None

def supports_gallerydl(url: str) -> bool:
    url = url.lower()
    return any(site in url for site in (
        "imgur.com", "i.imgur.com", "reddit.com", "redd.it", "pixiv.net",
        "twitter.com", "x.com", "tumblr.com", "flickr.com", "deviantart.com",
    ))

def supports_streamlink(url: str) -> bool:
    try:
        res = subprocess.run(
            [
                get_python(), "-c",
                f"import sys;sys.path.insert(0, '{STREAMLINK_PKG}');import streamlink;import sys as _s;_s.exit(0 if streamlink.streams(sys.argv[1]) else 1)",
                url,
            ],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return res.returncode == 0
    except Exception:
        return False

def _parse_url_normalize_map() -> dict[str, str]:
    raw = str(globals().get("URL_NORMALIZE", "")).strip()
    result = {}
    for pair in raw.split(","):
        pair = pair.strip()
        if ":" in pair:
            src, _, dst = pair.partition(":")
            src, dst = src.strip(), dst.strip()
            if src and dst:
                result[src] = dst
    return result

def normalize_url(url: str) -> str:
    for src, dst in _parse_url_normalize_map().items():
        if src in url:
            return url.replace(src, dst)
    return url

def _get_force_domains() -> list[str]:
    raw = str(globals().get("YTDLP_FORCE_DOMAINS", "")).strip()
    return [d.strip() for d in raw.split(",") if d.strip()]

def _add_force_domain(domain: str):
    domains = _get_force_domains()
    if domain not in domains:
        domains.append(domain)
    raw = read_config_file(CONFIG_FILE)
    raw["YTDLP_FORCE_DOMAINS"] = ",".join(domains)
    canonical = {k: raw.get(k, str(CONFIG_SCHEMA[k])) for k in CONFIG_SCHEMA}
    write_config_file(CONFIG_FILE, canonical, with_comments=True)
    globals()["YTDLP_FORCE_DOMAINS"] = ",".join(domains)

def _prompt_try_anyway(url: str):
    err("No supported extractor found")
    ans = safe_input("Try with yt-dlp anyway? [y/N]: ").strip().lower()
    if ans != "y":
        return

    cmd = _ytdlp_cmd(["-f", "bestvideo+bestaudio/best", "--remux-video", "mp4",
        "--concurrent-fragments", "8", "--no-part", "--no-mtime",
        "--merge-output-format", "mp4", "--write-info-json",
        "-o", str(DOWNLOAD / "%(title)s.%(ext)s"), url])
    result = subprocess.run(cmd, check=False)

    if result.returncode != 0:
        err("yt-dlp also failed — site may not be supported")
        return

    from urllib.parse import urlparse
    domain = urlparse(url).netloc

    if bool(globals().get("AUTO_ADD_FORCE_DOMAINS", True)):
        _add_force_domain(domain)
        ok(f"Added '{domain}' to YTDLP_FORCE_DOMAINS in config")
    else:
        ans2 = safe_input(f"Worked! Add '{domain}' to force-list so it's auto-detected next time? [y/N]: ").strip().lower()
        if ans2 == "y":
            _add_force_domain(domain)
            ok(f"Added '{domain}' to YTDLP_FORCE_DOMAINS in config")

    info_files = list(DOWNLOAD.glob("*.info.json"))
    if not info_files:
        warn("No info.json found, skipping")
        return

    info = info_files[0]
    candidates = [
        p for p in DOWNLOAD.iterdir()
        if p.is_file() and not p.name.endswith(".info.json") and p.suffix not in (".part", ".jpg", ".webp")
    ]

    if not candidates:
        warn("No media file found, skipping")
        info.unlink()
        return

    media = max(candidates, key=lambda p: p.stat().st_mtime)
    h = sha256_file(media)
    media_dest = SCRAPED / media.name
    media.rename(media_dest)

    d = json.load(open(info))
    d["media_sha256"] = h
    d["_filename"] = media_dest.name
    dest = JSON_DB / f"{secrets.token_hex(JSON_ID_BYTES)}.json"
    json.dump(d, open(dest, "w"), indent=2)

    index = json.load(open(SHA_INDEX))
    index[h] = str(media_dest)
    json.dump(index, open(SHA_INDEX, "w"), indent=2)

    ok(media_dest.name)
    log_download("scrape", url, media_dest)
    reset_download_dir()

def detect_extractor(url: str) -> Extractor:
    if supports_gallerydl(url):
        return "gallery-dl"

    from urllib.parse import urlparse
    domain = urlparse(url).netloc
    if any(d in domain for d in _get_force_domains()):
        return "yt-dlp"

    if get_ytdlp_meta(url) is not None:
        return "yt-dlp"

    if supports_streamlink(url):
        return "streamlink"

    return "none"

# =======================
# DB COMMANDS
# =======================

def remove_media(sha_prefix: str):
    sha_prefix = sha_prefix.lower().strip()

    try:
        index = json.load(open(SHA_INDEX))
    except Exception:
        warn("SHA index unreadable")
        return

    matches = [h for h in index if h.lower().startswith(sha_prefix)]

    if not matches:
        warn("No matching hash found")
        return

    if len(matches) > 1:
        warn("Ambiguous hash prefix:")
        for h in matches:
            print(" ", h[:16])
        return

    h = matches[0]
    media = Path(index[h])

    if not media.exists():
        warn("Media file not found. Run 'update database' or remove manually.")
        return

    media.unlink()
    del index[h]

    with open(SHA_INDEX, "w") as f:
        json.dump(index, f, indent=2)

    ok(f"Removed media {media.name}")

def run_db_list() -> None:
    try:
        data = json.load(open(SHA_INDEX))
    except Exception:
        data = {}

    if not data:
        warn("No files in database")
        return

    # Calculate total size
    total_size = 0
    for p in data.values():
        try:
            total_size += Path(p).stat().st_size
        except:
            pass

    total_gb = total_size / (1024 ** 3)

    print(f"\n\033[1;36m╔════════════════════════════════════════════════════════════════╗\033[0m")
    print(f"\033[1;36m║                    DATABASE CONTENTS                           ║\033[0m")
    print(f"\033[1;36m╚════════════════════════════════════════════════════════════════╝\033[0m\n")
    print(f"📂 Root: {SCRAPED}")
    print(f"📊 Files: {len(data)} | Size: {total_gb:.2f} GB\n")

    for i, (h, p) in enumerate(data.items(), 1):
        try:
            rel = Path(p).relative_to(SCRAPED)
            size = Path(p).stat().st_size / (1024 * 1024)
            max_chars = int(globals().get("LIST_NAME_MAX_CHARS", 30))
            name = str(rel)
            name = name[:max_chars] + "…" if len(name) > max_chars else name
            print(f"\033[0;36m{i:3}.\033[0m {h[:16]}... → {name} \033[0;90m({size:.1f} MB)\033[0m")
        except Exception:
            print(f"\033[0;36m{i:3}.\033[0m {h[:16]}... → {p} \033[0;31m(missing)\033[0m")
    print()

def run_db_update_json_names(length: int) -> None:
    length = length if 12 <= length <= 254 else 32
    for jf in JSON_DB.glob("*.json"):
        while True:
            nid = secrets.token_hex(length // 2)
            dest = JSON_DB / f"{nid}.json"
            if not dest.exists():
                jf.rename(dest)
                break
    ok("JSON filenames updated")

def run_db_update() -> None:
    _load_hash_cache()
    log("Rebuilding SHA index from JSON database")
    log_debug("Starting database rebuild")

    media_files = [Path(root) / f for root, _, files in os.walk(SCRAPED) for f in files]
    media_by_hash: dict[str, str] = {}
    media_by_name: dict[str, str] = {}  # filename → path (for stale-hash recovery)
    total_media = len(media_files)

    if total_media == 0:
        print("Hashing media: 0/0")
    else:
        import concurrent.futures
        workers = max(1, int(globals().get("HASH_WORKERS", 4)))
        completed = 0

        def _hash_one(p: Path):
            try:
                return sha256_file(p), str(p)
            except Exception:
                return None, None

        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(_hash_one, p): p for p in media_files}
            for fut in concurrent.futures.as_completed(futures):
                completed += 1
                digest, path_str = fut.result()
                if digest:
                    media_by_hash[digest] = path_str
                    media_by_name[Path(path_str).name] = path_str
                bar = progress_bar(completed, total_media, "Hashing media")
                print(f"\r{bar}", end="", flush=True)
        print()

    new_index = {}
    repaired = 0
    json_files = [p for p in JSON_DB.iterdir() if p.suffix == ".json"]
    total_json = len(json_files)

    if total_json == 0:
        print("Validating JSON: 0/0")
    else:
        for i, jf in enumerate(json_files, 1):
            try:
                d = json.load(open(jf))
                h = d.get("media_sha256")
                if not h:
                    jf.unlink()
                    continue

                p = media_by_hash.get(h)
                if p:
                    new_index[h] = p
                else:
                    # Hash is stale — recover by filename using multiple fallbacks:
                    # 1. our _filename field (just the name)
                    # 2. yt-dlp's native _filename (full path — take basename)
                    # 3. reconstruct from title + ext
                    raw = d.get("_filename") or ""
                    fname = (
                        raw if raw and "/" not in raw and "\\" not in raw
                        else Path(raw).name if raw
                        else ""
                    )
                    if not fname:
                        title = d.get("title") or ""
                        ext   = d.get("ext") or ""
                        if title and ext:
                            fname = f"{title}.{ext}"
                    candidate = media_by_name.get(fname) if fname else None
                    if candidate:
                        new_h = next((k for k, v in media_by_hash.items() if v == candidate), None)
                        if new_h:
                            d["media_sha256"] = new_h
                            json.dump(d, open(jf, "w"), indent=2)
                            new_index[new_h] = candidate
                            repaired += 1
                            continue
                    jf.unlink()
            except Exception:
                jf.unlink()
            bar = progress_bar(i, total_json, "Validating JSON")
            print(f"\r{bar}", end="", flush=True)
        print()
        if repaired:
            log(f"Repaired {repaired} stale hash(es) by filename match")

    with open(SHA_INDEX, "w") as fh:
        json.dump(new_index, fh, indent=2)

    new_vid = {}
    for jf in JSON_DB.glob("*.json"):
        try:
            d = json.load(open(jf))
            vid = d.get("id") or d.get("video_id")
            h = d.get("media_sha256")
            if vid and h and h in new_index:
                new_vid[vid] = h
        except Exception:
            pass

    json.dump(new_vid, open(VID_INDEX, "w"), indent=2)

    _save_hash_cache()
    ok(f"Database updated ({len(new_index)} entries)")
    log_debug("Database rebuild completed successfully")

def run_db_clear(keep_media: bool):
    run_db_update()
    if not keep_media:
        for p in json.load(open(SHA_INDEX)).values():
            try:
                Path(p).unlink()
            except Exception:
                pass
    for jf in JSON_DB.glob("*.json"):
        jf.unlink()
    SHA_INDEX.write_text("{}")
    VID_INDEX.write_text("{}")
    ok("Database cleared")

# =======================
# LOGGING (FILES)
# =======================

def run_log_command():
    files = {
        "general.log": GENERAL_LOG,
        "downloads.csv": DOWNLOADS_LOG,
        "debug.log": DEBUG_LOG,
    }

    if len(sys.argv) == 2:
        print("Available logs:")
        for f in files:
            print(" ", f)
        return

    name = sys.argv[2]
    path = files.get(name)

    if not path or not path.exists():
        err("Log file not found")
        return

    lines = None
    if len(sys.argv) > 3 and sys.argv[3].isdigit():
        lines = int(sys.argv[3])

    with open(path) as f:
        content = f.readlines()

    if name.endswith(".csv"):
        header = content[:1]
        body = content[1:]
        body = body[-lines:] if lines else body
        print("".join(header + body))
    else:
        out = content[-lines:] if lines else content
        print("".join(out))

def run_remove_logs():
    logs = get_log_files()

    if not logs:
        warn("No log files found")
        return

    if len(sys.argv) == 3:
        for p in logs.values():
            truncate_log(p)
        ok("All logs cleared")
        log_file("All logs truncated")
        return

    target = sys.argv[3]

    if target.isdigit():
        n = int(target)
        for p in logs.values():
            remove_oldest_lines(p, n)
        ok(f"Removed {n} oldest lines from all logs")
        log_file(f"Removed {n} oldest lines from all logs")
        return

    path = logs.get(target)
    if path and len(sys.argv) == 4:
        truncate_log(path)
        ok(f"{target} cleared")
        log_file(f"{target} truncated")
        return

    if path and len(sys.argv) == 5 and sys.argv[4].isdigit():
        n = int(sys.argv[4])
        remove_oldest_lines(path, n)
        ok(f"Removed {n} oldest lines from {target}")
        log_file(f"Removed {n} oldest lines from {target}")
        return

    err("Invalid remove logs usage")

def truncate_log(path: Path):
    path.write_text("")

def remove_oldest_lines(path: Path, count: int):
    if count <= 0 or not path.exists():
        return

    with open(path) as f:
        lines = f.readlines()

    if path.name.endswith(".csv") and lines:
        header = lines[:1]
        body = lines[1:]
        new_lines = header + body[count:]
    else:
        new_lines = lines[count:]

    with open(path, "w") as f:
        f.writelines(new_lines)

def get_log_files() -> dict[str, Path]:
    return {p.name: p for p in LOGS_DIR.iterdir() if p.is_file()}

# =======================
# QUEUE MODE
# =======================

def queue_mode_interactive():
    print('Enter: URL [quality] [format] — type "start" to begin, "cancel" to abort')
    while True:
        line = safe_input("> ").strip()
        if line == "start":
            break
        if line == "cancel":
            URLS.clear()
            warn("Queue cancelled")
            return
        parts = line.split()
        if not parts:
            continue
        url = parts[0]
        if not url.startswith("http"):
            warn("Invalid URL")
            continue
        quality = container = None

        for a in parts[1:]:
            if a in ("best", "high", "medium", "low"):
                quality = a
            elif a in ("mp4", "webm", "mkv"):
                container = a

        # Fast-track detection without blocking
        log("Processing URL...")
        extractor = detect_extractor(url)

        # Async parameter collection
        quality, container = prompt_for_extractor_params(extractor, quality, container)

        duration_flag = None
        if extractor == "yt-dlp":
            meta = get_ytdlp_meta(url)
            if is_live_from_meta(meta):
                duration_flag = prompt_live_duration()

        URLS.append(f"{url}|{quality}|{container}|{extractor}|{duration_flag}")
        ok("Added to queue")

def prompt_live_duration() -> str | None:
    while True:
        s = safe_input("Recording duration [Xs / Xm / Xh / manual] [manual]: ").strip().lower()

        if not s or s == "manual":
            return "manual"

        if re.fullmatch(r"\d+[smh]", s):
            return s

        warn("Invalid duration format")

# =======================
# PROCESS QUEUE
# =======================

def process_queue_and_exit_if_done():
    load_video_index()

    manual_lives, normal_queue = [], []

    for entry in URLS:
        parts = entry.split("|")
        while len(parts) < 5:
            parts.append(None)

        url, quality, container, extractor, duration_flag = parts
        meta = get_ytdlp_meta(url)

        if extractor == "yt-dlp" and is_live_from_meta(meta) and (not duration_flag or duration_flag == "manual"):
            manual_lives.append(entry)
        else:
            normal_queue.append(entry)

    URLS[:] = normal_queue + manual_lives

    for entry in URLS:
        log_debug(f"Processing queue entry: {entry}")
        parts = entry.split("|")
        while len(parts) < 5:
            parts.append(None)

        url, quality, container, extractor, duration_flag = parts
        url = normalize_url(url)

        if duration_flag in ("None", "", None):
            duration_flag = None

        meta = get_ytdlp_meta(url)
        is_live = extractor == "yt-dlp" and is_live_from_meta(meta)

        if duration_flag not in ("", None, "manual") and not is_live:
            warn("Duration flags are only supported for live streams — ignoring")
            duration_flag = None

        if is_live:
            if not duration_flag:
                duration_flag = prompt_live_duration()
            record_live_stream(url, quality, duration_flag)
            continue

        VID = None
        if extractor == "yt-dlp":
            VID = get_video_id_for_dedup(url)
            if video_id_exists(VID):
                warn("Already downloaded")
                continue

        if extractor == "yt-dlp":
            fmt = select_format(quality)
            cont = select_container(container)

            cmd = _ytdlp_cmd(["-f", fmt, "--remux-video", cont,
                "--concurrent-fragments", "8", "--file-access-retries", "3",
                "--fragment-retries", "3", "--retry-sleep", "fragment:1",
                "--no-part", "--no-mtime", "--merge-output-format", cont,
                "--write-info-json", "-o", str(DOWNLOAD / "%(title)s.%(ext)s"), url])
            subprocess.run(cmd, check=False)

        elif extractor == "streamlink":
            out = DOWNLOAD / f"stream_{int(time.time())}.ts"
            run_module(STREAMLINK_PKG, "streamlink", [url, quality or "best", "-o", str(out)])

        elif extractor == "gallery-dl":
            run_module(GALLERYDL_PKG, "gallery_dl", ["-d", str(DOWNLOAD), url])

        else:
            _prompt_try_anyway(url)
            continue

        if extractor == "gallery-dl":
            files = [p for p in DOWNLOAD.rglob("*") if p.is_file() and p.suffix.lower() not in (".json", ".txt")]

            if not files:
                warn("No files downloaded by gallery-dl")
                reset_download_dir()
                continue

            for media in files:
                h = sha256_file(media)
                media_dest = SCRAPED / media.name
                media.rename(media_dest)

                index = json.load(open(SHA_INDEX))
                index[h] = str(media_dest)
                json.dump(index, open(SHA_INDEX, "w"), indent=2)

                ok(media_dest.name)

            reset_download_dir()
            continue

        if extractor == "streamlink":
            files = list(DOWNLOAD.iterdir())
            if files:
                media = files[0]
                media_dest = SCRAPED / media.name
                media.rename(media_dest)
                ok(media_dest.name)

            reset_download_dir()
            continue

        log_debug(f"yt-dlp finished for URL {url}")

        info_files = list(DOWNLOAD.glob("*.info.json"))
        if not info_files:
            warn("No info.json found, skipping")
            continue

        info = info_files[0]

        candidates = [
            p for p in DOWNLOAD.iterdir()
            if p.is_file() and not p.name.endswith(".info.json") and p.suffix not in (".part", ".jpg", ".webp")
        ]

        if not candidates:
            warn("No media file found, skipping")
            info.unlink()
            continue

        media = max(candidates, key=lambda p: p.stat().st_mtime)
        h = sha256_file(media)
        media_dest = SCRAPED / media.name
        media.rename(media_dest)

        d = json.load(open(info))
        d["media_sha256"] = h
        d["_filename"] = media_dest.name
        dest = JSON_DB / f"{secrets.token_hex(JSON_ID_BYTES)}.json"
        json.dump(d, open(dest, "w"), indent=2)

        index = json.load(open(SHA_INDEX))
        index[h] = str(media_dest)
        json.dump(index, open(SHA_INDEX, "w"), indent=2)

        VIDEO_ID_CACHE[VID] = h
        ok(media.name)

        log_download("queue" if CMD == "queue" else "scrape", url, media_dest)
        reset_download_dir()

    json.dump(VIDEO_ID_CACHE, open(VID_INDEX, "w"), indent=2)
    ok("Done")
    sys.exit(0)

def uninstall_all():
    log_file("Uninstall invoked")
    log_debug("Uninstall started — deleting DATA directory")
    if DATA.exists():
        shutil.rmtree(DATA)
        ok("Data directory removed")
    else:
        warn("No data directory found")

    os._exit(0)

def clear_screen():
    os.system("cls" if os.name == "nt" else "clear")

def handle_remove_command(argv: list[str]):
    parts = argv[2:]

    if not parts:
        warn("No hash provided")
        return

    if parts[0] == "sha":
        if len(parts) < 2:
            warn("No SHA provided")
            return
        remove_media(parts[1])
        return

    remove_media(parts[0])

def print_banner():
    banner = """
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║     ███████╗ ██████╗██████╗  █████╗ ██████╗ ███████╗██████╗               ║
║     ██╔════╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗              ║
║     ███████╗██║     ██████╔╝███████║██████╔╝█████╗  ██║  ██║              ║
║     ╚════██║██║     ██╔══██╗██╔══██║██╔═══╝ ██╔══╝  ██║  ██║              ║
║     ███████║╚██████╗██║  ██║██║  ██║██║     ███████╗██████╔╝              ║
║     ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚═════╝               ║
║                                                                            ║
║              🎬 Multi-Platform Media Archival & Management Tool            ║
║              📦 Supports: YouTube, Twitch, Twitter, Reddit & More          ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
    """
    print(f"\033[1;36m{banner}\033[0m")

def interactive_shell():
    try:
        _interactive_shell_loop()
    finally:
        disable_interactive_delays()

def _interactive_shell_loop():
    while True:
        try:
            line = safe_input('> Enter your command [or "help"]: ').strip()
            log_debug(f"User input: {line}")
        except EOFError:
            break

        if not line:
            continue

        if line in ("exit", "quit"):
            break

        clear_screen()

        global _ANIMATION_LINE_COUNTER
        _ANIMATION_LINE_COUNTER = 0

        argv_backup = sys.argv
        args = normalize_command(line)
        sys.argv = ["scraped"] + args

        try:
            parse_args_and_prepare()

            if CMD == "download":
                if len(sys.argv) < 3:
                    prefix = safe_input("Enter hash prefix: ").strip()
                    if not prefix:
                        err("No hash provided")
                        continue
                else:
                    prefix = sys.argv[2]

                dest = Path(sys.argv[3]) if len(sys.argv) > 3 else None
                export_by_hash(prefix, dest)

            elif CMD == "queue":
                URLS.clear()
                queue_mode_interactive()
                process_queue_and_exit_if_done()

            elif CMD == "list":
                run_db_list()

            elif CMD == "remove":
                if len(sys.argv) < 3:
                    err("Missing target")
                else:
                    logs = get_log_files()
                    target = sys.argv[2]

                    if target == "logs":
                        run_remove_logs()

                    elif target in logs and len(sys.argv) > 3 and sys.argv[3].isdigit():
                        remove_oldest_lines(logs[target], int(sys.argv[3]))
                        ok(f"Removed {sys.argv[3]} oldest lines from {target}")
                        log_file(f"Removed {sys.argv[3]} oldest lines from {target}")

                    elif target in logs:
                        truncate_log(logs[target])
                        ok(f"{target} cleared")
                        log_file(f"{target} truncated")

                    else:
                        handle_remove_command(sys.argv)

            elif CMD == "update":
                run_update()

            elif CMD == "config":
                run_config_command()

            elif CMD == "scrape":
                process_queue_and_exit_if_done()

            elif CMD == "help":
                usage()

            elif CMD == "log":
                run_log_command()

            elif CMD == "supported":
                if SUB:
                    check_supported(SUB)
                else:
                    list_supported()

            elif CMD == "host":
                run_host_command()

            else:
                err("Unknown command")

        except SystemExit:
            pass
        finally:
            sys.argv = argv_backup

def normalize_command(line: str) -> list[str]:
    return line.strip().split()

# =======================
# HOST SERVER
# =======================

def kill_orphaned_servers():
    """Kill any orphaned server processes from previous runs"""
    try:
        if HOST_PID_FILE.exists():
            pid_data = json.loads(HOST_PID_FILE.read_text())
            pid = pid_data.get("pid")
            if pid:
                try:
                    if os.name == "nt":
                        subprocess.run(["taskkill", "/F", "/PID", str(pid)],
                                     stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
                    else:
                        os.kill(pid, signal.SIGTERM)
                    log_debug(f"Killed orphaned server process {pid}")
                except Exception:
                    pass
            HOST_PID_FILE.unlink()
    except Exception:
        pass

def get_host_status() -> dict:
    """Get current host server status"""
    if not HOST_PID_FILE.exists():
        return {"running": False, "mode": None, "port": None, "attached": None}

    try:
        data = json.loads(HOST_PID_FILE.read_text())
        pid = data.get("pid")

        # Check if process is actually running
        if pid:
            try:
                if os.name == "nt":
                    result = subprocess.run(["tasklist", "/FI", f"PID eq {pid}"],
                                          capture_output=True, text=True)
                    running = str(pid) in result.stdout
                else:
                    os.kill(pid, 0)
                    running = True
            except (OSError, subprocess.SubprocessError):
                running = False
        else:
            running = False

        if not running:
            HOST_PID_FILE.unlink()
            return {"running": False, "mode": None, "port": None, "attached": None}

        return {
            "running": True,
            "mode": data.get("mode"),
            "port": data.get("port"),
            "attached": data.get("attached"),
            "pid": pid
        }
    except Exception:
        return {"running": False, "mode": None, "port": None, "attached": None}

def run_host_status():
    """Display host server status"""
    status = get_host_status()

    print("\n\033[1;36m╔════════════════════════════════════════╗\033[0m")
    print("\033[1;36m║       WEB SERVER STATUS                ║\033[0m")
    print("\033[1;36m╚════════════════════════════════════════╝\033[0m\n")

    if status["running"]:
        mode_color = "\033[1;32m" if status["mode"] == "private" else "\033[1;33m"
        print(f"Status:   \033[1;32m●\033[0m ONLINE")
        print(f"Mode:     {mode_color}{status['mode'].upper()}\033[0m")
        print(f"Port:     {status['port']}")
        print(f"Attached: {'Yes' if status['attached'] else 'No (Background)'}")
        print(f"PID:      {status.get('pid', 'N/A')}")

        if status["mode"] == "private":
            print(f"\nAccess:   \033[1;36mhttp://localhost:{status['port']}\033[0m")
        else:
            import socket
            hostname = socket.gethostname()
            local_ip = socket.gethostbyname(hostname)
            print(f"\nLocal:    \033[1;36mhttp://localhost:{status['port']}\033[0m")
            print(f"Network:  \033[1;36mhttp://{local_ip}:{status['port']}\033[0m")
    else:
        print(f"Status:   \033[1;31m●\033[0m OFFLINE")
        print(f"Port:     {HOST_PORT} (default)")
    print()

def start_host_server(mode: str, detached: bool = False):
    """Start the web server in private or public mode"""
    status = get_host_status()
    if status["running"]:
        warn(f"Server already running in {status['mode']} mode on port {status['port']}")
        return

    if mode not in ("private", "public"):
        err("Invalid mode. Use 'private' or 'public'")
        return

    host = "127.0.0.1" if mode == "private" else "0.0.0.0"
    port = HOST_PORT

    # Create minimal HTTP server script
    server_script = TEMP / "host_server.py"
    server_script.write_text(f'''
import http.server
import socketserver
import os
import json
import mimetypes
import urllib.parse
from pathlib import Path

PORT = {port}
HOST = "{host}"
SCRAPED_DIR = r"{SCRAPED}"
DB_DIR = r"{DB}"
JSON_DB_DIR = r"{JSON_DB}"
MEDIA_PREVIEW_MODE = "{MEDIA_PREVIEW_MODE}"
MEDIA_PREVIEW_SEEK_SEC = {MEDIA_PREVIEW_SEEK_SEC}

class MediaHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # suppress stderr logging — fills pipe buffer and deadlocks

    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()

            html = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>Scraped Media Server</title>
                <style>
                    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
                    body {{
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                        background: #111;
                        color: #e0e0e0;
                        min-height: 100vh;
                    }}
                    header {{
                        background: #161616;
                        border-bottom: 1px solid #2a2a2a;
                        padding: 18px 32px;
                        display: flex;
                        align-items: center;
                        justify-content: space-between;
                        position: sticky;
                        top: 0;
                        z-index: 10;
                    }}
                    header h1 {{
                        font-size: 1.3rem;
                        font-weight: 600;
                        color: #fff;
                        letter-spacing: 0.02em;
                    }}
                    .stats-bar {{
                        font-size: 0.85rem;
                        color: #888;
                    }}
                    .stats-bar span {{ color: #4a9eff; font-weight: 500; }}
                    .search-wrap {{
                        padding: 24px 32px 8px;
                    }}
                    .search-wrap input {{
                        width: 100%;
                        max-width: 480px;
                        background: #1e1e1e;
                        border: 1px solid #2e2e2e;
                        border-radius: 8px;
                        padding: 10px 16px;
                        color: #e0e0e0;
                        font-size: 0.95rem;
                        outline: none;
                        transition: border-color 0.15s;
                    }}
                    .search-wrap input:focus {{ border-color: #4a9eff; }}
                    .search-wrap input::placeholder {{ color: #555; }}
                    main {{
                        padding: 20px 32px 48px;
                        display: grid;
                        grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
                        gap: 16px;
                    }}
                    .card {{
                        background: #1a1a1a;
                        border: 1px solid #242424;
                        border-radius: 10px;
                        padding: 16px;
                        display: flex;
                        flex-direction: column;
                        gap: 10px;
                        transition: border-color 0.15s, transform 0.1s;
                    }}
                    .card:hover {{
                        border-color: #3a3a3a;
                        transform: translateY(-2px);
                    }}
                    .card-title {{
                        font-size: 0.92rem;
                        font-weight: 500;
                        color: #ddd;
                        line-height: 1.4;
                        flex: 1;
                    }}
                    .card-meta {{
                        font-size: 0.78rem;
                        color: #555;
                    }}
                    .card-actions {{
                        display: flex;
                        gap: 8px;
                    }}
                    .card-thumb {{
                        width: 100%;
                        aspect-ratio: 16/9;
                        border-radius: 6px;
                        background: #111;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        cursor: pointer;
                        transition: background 0.15s;
                        position: relative;
                        overflow: hidden;
                    }}
                    .card-thumb:hover {{ background: #1a1a1a; }}
                    .card-thumb svg {{ opacity: 0.35; transition: opacity 0.15s; position: relative; z-index: 1; }}
                    .card-thumb:hover svg {{ opacity: 0.7; }}
                    .card-thumb img {{
                        position: absolute; inset: 0;
                        width: 100%; height: 100%;
                        object-fit: cover;
                        border-radius: 6px;
                    }}
                    .card-thumb img + svg {{ opacity: 0; }}
                    .card-thumb:hover img + svg {{ opacity: 0.7; }}
                    .card-video {{
                        width: 100%;
                        aspect-ratio: 16/9;
                        object-fit: cover;
                        border-radius: 6px;
                        background: #0d0d0d;
                        display: block;
                        cursor: pointer;
                    }}
                    .modal-overlay {{
                        display: none;
                        position: fixed;
                        inset: 0;
                        background: rgba(0,0,0,0.88);
                        z-index: 1000;
                        align-items: center;
                        justify-content: center;
                        flex-direction: column;
                        gap: 12px;
                    }}
                    .modal-overlay.open {{
                        display: flex;
                    }}
                    .modal-video {{
                        max-width: 92vw;
                        max-height: 80vh;
                        border-radius: 8px;
                        box-shadow: 0 8px 48px rgba(0,0,0,0.8);
                        background: #000;
                    }}
                    .modal-title {{
                        color: #ccc;
                        font-size: 0.9rem;
                        max-width: 92vw;
                        text-align: center;
                        overflow: hidden;
                        text-overflow: ellipsis;
                        white-space: nowrap;
                    }}
                    .modal-close {{
                        position: fixed;
                        top: 16px;
                        right: 20px;
                        background: none;
                        border: none;
                        color: #888;
                        font-size: 1.6rem;
                        cursor: pointer;
                        line-height: 1;
                    }}
                    .modal-close:hover {{ color: #fff; }}
                    .btn-dl {{
                        display: inline-block;
                        background: #1e3a5f;
                        color: #4a9eff;
                        border: 1px solid #1e4a7a;
                        border-radius: 6px;
                        padding: 6px 14px;
                        font-size: 0.82rem;
                        font-weight: 500;
                        text-decoration: none;
                        transition: background 0.15s, border-color 0.15s;
                    }}
                    .btn-dl:hover {{
                        background: #1e4a7a;
                        border-color: #4a9eff;
                    }}
                    .empty {{ padding: 48px 32px; color: #555; font-size: 0.95rem; }}
                </style>
            </head>
            <body>
                <header>
                    <h1>Scraped Media Server</h1>
                    <div class="stats-bar" id="stats">Loading...</div>
                </header>
                <div class="search-wrap">
                    <input type="text" id="search" placeholder="Search titles..." oninput="filterCards()">
                </div>
                <main id="media-list"></main>

                <div class="modal-overlay" id="modal" onclick="closeModal(event)">
                    <button class="modal-close" onclick="closeModal(null, true)">&times;</button>
                    <video class="modal-video" id="modal-video" controls></video>
                    <div class="modal-title" id="modal-title"></div>
                </div>

                <script>
                    let allFiles = [];

                    fetch('/api/list')
                        .then(r => r.json())
                        .then(data => {{
                            allFiles = data.files;
                            document.getElementById('stats').innerHTML =
                                `<span>${{data.files.length}}</span> files &nbsp;·&nbsp; <span>${{(data.total_size / 1024 / 1024 / 1024).toFixed(2)}} GB</span>`;
                            renderCards(allFiles);
                            generateThumbnails();
                        }});

                    const PREVIEW_MODE = {json.dumps(MEDIA_PREVIEW_MODE)};
                    const SEEK_SEC = {MEDIA_PREVIEW_SEEK_SEC};
                    const thumbCache = {{}};

                    function playIcon() {{
                        return `<svg width="48" height="48" viewBox="0 0 48 48" fill="white">
                            <circle cx="24" cy="24" r="22" fill="none" stroke="white" stroke-width="2" opacity="0.5"/>
                            <polygon points="19,14 37,24 19,34" fill="white"/>
                        </svg>`;
                    }}

                    function cardPreview(file) {{
                        const src = `/media/${{encodeURIComponent(file.name)}}`;
                        // use data attributes — avoids breakage from titles with quotes/apostrophes
                        if (PREVIEW_MODE === 'preview') {{
                            return `<video class="card-thumb card-video" preload="none" muted playsinline loop
                                data-mediasrc="${{src}}" data-title="${{encodeURIComponent(file.title || file.name)}}"
                                onmouseenter="hoverPlay(this)" onmouseleave="hoverStop(this)">${{playIcon()}}</video>`;
                        }}
                        const cached = PREVIEW_MODE === 'thumbnail' ? thumbCache[file.name] : null;
                        const extra = PREVIEW_MODE === 'thumbnail' && !cached
                            ? ` data-mediasrc="${{src}}" data-name="${{encodeURIComponent(file.name)}}"` : '';
                        const img = cached ? `<img src="${{cached}}" loading="lazy">` : '';
                        return `<div class="card-thumb"${{extra}}
                            data-title="${{encodeURIComponent(file.title || file.name)}}"
                            data-mediasrc="${{src}}">${{img}}${{playIcon()}}</div>`;
                    }}

                    function generateThumbnails() {{
                        if (PREVIEW_MODE !== 'thumbnail') return;
                        const pending = document.querySelectorAll('.card-thumb[data-name]');
                        const canvas = document.createElement('canvas');
                        canvas.width = 320; canvas.height = 180;
                        const ctx = canvas.getContext('2d');
                        let i = 0;
                        function next() {{
                            if (i >= pending.length) return;
                            const el = pending[i++];
                            const src = el.dataset.mediasrc;
                            const name = decodeURIComponent(el.dataset.name);
                            if (thumbCache[name]) {{ injectThumb(el, thumbCache[name], name); next(); return; }}
                            const v = document.createElement('video');
                            v.muted = true; v.preload = 'metadata';
                            v.src = src + '#t=' + SEEK_SEC;
                            v.onloadeddata = () => {{
                                ctx.drawImage(v, 0, 0, 320, 180);
                                const dataUrl = canvas.toDataURL('image/jpeg', 0.6);
                                thumbCache[name] = dataUrl;
                                injectThumb(el, dataUrl, name);
                                v.src = '';
                                setTimeout(next, 50);
                            }};
                            v.onerror = () => {{ v.src = ''; setTimeout(next, 50); }};
                        }}
                        for (let k = 0; k < Math.min(3, pending.length); k++) next();
                    }}

                    function injectThumb(el, dataUrl, name) {{
                        const img = document.createElement('img');
                        img.src = dataUrl;
                        img.loading = 'lazy';
                        el.insertBefore(img, el.firstChild);
                        el.removeAttribute('data-name');
                    }}

                    function hoverPlay(v) {{
                        if (!v.src) {{ v.src = v.dataset.mediasrc + '#t=' + SEEK_SEC; v.load(); }}
                        v.play().catch(() => {{}});
                    }}

                    function hoverStop(v) {{
                        v.pause(); v.currentTime = SEEK_SEC;
                    }}

                    let _canplayHandler = null;

                    function openModal(src, title) {{
                        const mv = document.getElementById('modal-video');
                        mv.pause();
                        if (_canplayHandler) {{ mv.removeEventListener('canplay', _canplayHandler); _canplayHandler = null; }}
                        mv.src = src;
                        mv.load();
                        _canplayHandler = () => {{
                            mv.play().catch(e => console.error('play failed:', e));
                            _canplayHandler = null;
                        }};
                        mv.addEventListener('canplay', _canplayHandler, {{once: true}});
                        document.getElementById('modal-title').textContent = decodeURIComponent(title);
                        document.getElementById('modal').classList.add('open');
                    }}

                    // delegated click — avoids inline onclick breakage with special chars
                    document.getElementById('media-list').addEventListener('click', e => {{
                        const thumb = e.target.closest('.card-thumb');
                        if (!thumb) return;
                        openModal(thumb.dataset.mediasrc, thumb.dataset.title || '');
                    }});

                    function closeModal(e, force) {{
                        if (force || (e && e.target === document.getElementById('modal'))) {{
                            const mv = document.getElementById('modal-video');
                            if (_canplayHandler) {{ mv.removeEventListener('canplay', _canplayHandler); _canplayHandler = null; }}
                            mv.pause();
                            document.getElementById('modal').classList.remove('open');
                        }}
                    }}

                    document.addEventListener('keydown', e => {{ if (e.key === 'Escape') closeModal(null, true); }});

                    function renderCards(files) {{
                        const grid = document.getElementById('media-list');
                        if (!files.length) {{ grid.innerHTML = '<div class="empty">No files found.</div>'; return; }}
                        grid.innerHTML = files.map(file => `
                            <div class="card" data-name="${{(file.title || file.name).toLowerCase()}}">
                                ${{cardPreview(file)}}
                                <div class="card-title">${{file.title || file.name}}</div>
                                <div class="card-meta">${{(file.size / 1024 / 1024).toFixed(1)}} MB</div>
                                <div class="card-actions">
                                    <a class="btn-dl" href="/media/${{encodeURIComponent(file.name)}}" download="${{file.name}}">Download</a>
                                </div>
                            </div>
                        `).join('');
                    }}

                    function filterCards() {{
                        const q = document.getElementById('search').value.toLowerCase();
                        renderCards(allFiles.filter(f => (f.title || f.name).toLowerCase().includes(q)));
                        generateThumbnails();
                    }}
                </script>
            </body>
            </html>
            """
            self.wfile.write(html.encode())

        elif self.path == "/api/list":
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()

            files = []
            total_size = 0
            scraped_path = Path(SCRAPED_DIR)

            for file in scraped_path.rglob("*"):
                if file.is_file():
                    size = file.stat().st_size
                    total_size += size

                    # Try to get metadata
                    title = file.stem
                    try:
                        sha_index = json.loads(Path(DB_DIR, "sha256", "index.json").read_text())
                        for h, p in sha_index.items():
                            if str(file) == p:
                                # Find matching JSON
                                for json_file in Path(JSON_DB_DIR).glob("*.json"):
                                    data = json.loads(json_file.read_text())
                                    if data.get("media_sha256") == h:
                                        title = data.get("title", title)
                                        break
                                break
                    except:
                        pass

                    files.append({{
                        "name": file.name,
                        "title": title,
                        "size": size,
                        "path": str(file.relative_to(scraped_path))
                    }})

            result = {{"files": files, "total_size": total_size}}
            self.wfile.write(json.dumps(result).encode())

        elif self.path.startswith("/media/"):
            filename = urllib.parse.unquote(self.path[7:].split("?")[0])
            file_path = Path(SCRAPED_DIR) / filename

            if file_path.exists() and file_path.is_file():
                mime, _ = mimetypes.guess_type(str(file_path))
                mime = mime or "application/octet-stream"
                size = file_path.stat().st_size
                range_header = self.headers.get("Range")

                if range_header and range_header.startswith("bytes="):
                    try:
                        rng = range_header[6:].split("-")
                        start = int(rng[0]) if rng[0] else 0
                        end   = int(rng[1]) if rng[1] else size - 1
                        end   = min(end, size - 1)
                        length = end - start + 1
                        self.send_response(206)
                        self.send_header("Content-Type", mime)
                        self.send_header("Content-Range", f"bytes {{start}}-{{end}}/{{size}}")
                        self.send_header("Content-Length", str(length))
                        self.send_header("Accept-Ranges", "bytes")
                        self.end_headers()
                        with open(file_path, "rb") as f:
                            f.seek(start)
                            remaining = length
                            while remaining > 0:
                                chunk = f.read(min(65536, remaining))
                                if not chunk:
                                    break
                                self.wfile.write(chunk)
                                remaining -= len(chunk)
                    except Exception:
                        self.send_response(416)
                        self.end_headers()
                else:
                    self.send_response(200)
                    self.send_header("Content-Type", mime)
                    self.send_header("Content-Length", str(size))
                    self.send_header("Accept-Ranges", "bytes")
                    self.send_header("Content-Disposition", f'inline; filename="{{filename}}"')
                    self.end_headers()
                    with open(file_path, "rb") as f:
                        while True:
                            chunk = f.read(65536)
                            if not chunk:
                                break
                            self.wfile.write(chunk)
            else:
                self.send_response(404)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True

os.chdir(r"{SCRAPED}")
with ThreadedTCPServer((HOST, PORT), MediaHandler) as httpd:
    print(f"Server running on {{HOST}}:{{PORT}}")
    httpd.serve_forever()
''', encoding='utf-8')

    # Start server
    if detached or not HOST_ATTACHED:
        # Background mode
        if os.name == "nt":
            proc = subprocess.Popen(
                [get_python(), str(server_script)],
                creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
        else:
            proc = subprocess.Popen(
                [get_python(), str(server_script)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True
            )

        # Save PID
        HOST_PID_FILE.write_text(json.dumps({
            "pid": proc.pid,
            "mode": mode,
            "port": port,
            "attached": False
        }))

        ok(f"Server started in background ({mode} mode) on port {port}")
        if mode == "private":
            print(f"   Access at: \033[1;36mhttp://localhost:{port}\033[0m")
        else:
            import socket
            local_ip = socket.gethostbyname(socket.gethostname())
            print(f"   Local:   \033[1;36mhttp://localhost:{port}\033[0m")
            print(f"   Network: \033[1;36mhttp://{local_ip}:{port}\033[0m")
    else:
        # Attached mode
        global HOST_SERVER_PROCESS
        HOST_SERVER_PROCESS = subprocess.Popen(
            [get_python(), str(server_script)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        HOST_PID_FILE.write_text(json.dumps({
            "pid": HOST_SERVER_PROCESS.pid,
            "mode": mode,
            "port": port,
            "attached": True
        }))

        ok(f"Server started ({mode} mode) on port {port}")
        if mode == "private":
            print(f"   Access at: \033[1;36mhttp://localhost:{port}\033[0m")
        else:
            import socket
            local_ip = socket.gethostbyname(socket.gethostname())
            print(f"   Local:   \033[1;36mhttp://localhost:{port}\033[0m")
            print(f"   Network: \033[1;36mhttp://{local_ip}:{port}\033[0m")

def stop_host_server():
    """Stop the web server"""
    status = get_host_status()
    if not status["running"]:
        warn("Server is not running")
        return

    try:
        pid = status["pid"]
        if os.name == "nt":
            subprocess.run(["taskkill", "/F", "/PID", str(pid)],
                         stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
        else:
            os.kill(pid, signal.SIGTERM)

        if HOST_PID_FILE.exists():
            HOST_PID_FILE.unlink()

        global HOST_SERVER_PROCESS
        HOST_SERVER_PROCESS = None

        ok("Server stopped")
    except Exception as e:
        err(f"Failed to stop server: {e}")

def detach_host_server():
    """Detach server from TUI (run in background)"""
    status = get_host_status()
    if not status["running"]:
        warn("Server is not running")
        return

    if not status["attached"]:
        warn("Server is already detached")
        return

    # Update status to detached
    try:
        data = json.loads(HOST_PID_FILE.read_text())
        data["attached"] = False
        HOST_PID_FILE.write_text(json.dumps(data))
        ok("Server detached - now running in background")
    except Exception as e:
        err(f"Failed to detach server: {e}")

def attach_host_server():
    """Attach server back to TUI"""
    status = get_host_status()
    if not status["running"]:
        warn("Server is not running")
        return

    if status["attached"]:
        warn("Server is already attached")
        return

    try:
        data = json.loads(HOST_PID_FILE.read_text())
        data["attached"] = True
        HOST_PID_FILE.write_text(json.dumps(data))
        ok("Server attached to TUI")
    except Exception as e:
        err(f"Failed to attach server: {e}")

def kill_all_host_servers():
    """Force kill all server processes"""
    killed = 0

    # Kill PID file process
    if HOST_PID_FILE.exists():
        try:
            data = json.loads(HOST_PID_FILE.read_text())
            pid = data.get("pid")
            if pid:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/F", "/PID", str(pid)],
                                 stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
                else:
                    os.kill(pid, signal.SIGKILL)
                killed += 1
        except Exception:
            pass
        HOST_PID_FILE.unlink()

    # Search for orphaned processes
    try:
        if os.name == "nt":
            result = subprocess.run(
                ["tasklist", "/FI", "IMAGENAME eq python.exe", "/FO", "CSV"],
                capture_output=True, text=True
            )
            for line in result.stdout.splitlines()[1:]:
                parts = line.split('","')
                if len(parts) >= 2:
                    pid = parts[1].strip('"')
                    # Check if it's our server
                    try:
                        subprocess.run(["taskkill", "/F", "/PID", pid],
                                     stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
                        killed += 1
                    except:
                        pass
        else:
            result = subprocess.run(
                ["pgrep", "-f", "host_server.py"],
                capture_output=True, text=True
            )
            for pid in result.stdout.strip().split('\n'):
                if pid:
                    try:
                        os.kill(int(pid), signal.SIGKILL)
                        killed += 1
                    except:
                        pass
    except Exception:
        pass

    global HOST_SERVER_PROCESS
    HOST_SERVER_PROCESS = None

    ok(f"Killed {killed} server process(es)")

def run_host_command():
    """Handle host server commands"""
    sub = SUB.lower() if isinstance(SUB, str) else ""

    if sub == "status":
        run_host_status()
        return

    if sub == "public":
        start_host_server("public", detached=False)
        return

    if sub == "private":
        start_host_server("private", detached=False)
        return

    if sub == "offline":
        stop_host_server()
        return

    if sub == "detach":
        detach_host_server()
        return

    if sub == "attach":
        attach_host_server()
        return

    if sub == "kill":
        kill_all_host_servers()
        return

    err("Invalid host subcommand (status | public | private | offline | detach | attach | kill)")

# =======================
# MAIN
# =======================

def main():
    global LOGO_IS_ABOVE_LOG

    # Kill orphaned servers first
    with redirect_stdout(_STARTUP_STDOUT):
        kill_orphaned_servers()

    if len(sys.argv) == 1:
        enable_interactive_delays()

        ok_keys, bad_keys, orphan_keys = _CONFIG_RESULT

        if DETAILLED_STARTUP_LOG:
            if bad_keys or orphan_keys:
                warn(
                    f"Config had issues and was auto-repaired "
                    f"({len(bad_keys)} invalid, {len(orphan_keys)} orphan)"
                )

            ok("Config loaded into RAM")
            startup_report(interactive=True)

            print_banner()

            buffered_output = _STARTUP_STDOUT.getvalue()
            for line in buffered_output.splitlines():
                if line.strip():
                    print(line)

            LOGO_IS_ABOVE_LOG = False

        else:
            LOGO_IS_ABOVE_LOG = False
            if bad_keys or orphan_keys:
                warn(
                    f"Config had issues and was auto-repaired "
                    f"({len(bad_keys)} invalid, {len(orphan_keys)} orphan)"
                )
            ok("Config loaded into RAM")

        print()
        print("Type 'help' for commands · 'exit' to quit")
        print()

        # Auto-start server if configured
        if STARTUP_HOST in ("private", "public"):
            start_host_server(STARTUP_HOST, detached=not HOST_ATTACHED)

        interactive_shell()
        return

    parse_args_and_prepare()

    if CMD == "download":
        if len(sys.argv) < 3:
            url = safe_input("Enter download URL: ").strip()
            if not url:
                err("No URL provided")
                return
        else:
            url = sys.argv[2]

        quick_download(url)
        return

    if CMD == "scrape":
        process_queue_and_exit_if_done()
        return

    if CMD == "queue":
        queue_mode_interactive()
        process_queue_and_exit_if_done()
        return

    if CMD == "list":
        run_db_list()
        return

    if CMD == "remove":
        if len(sys.argv) < 3:
            err("Missing target")
            return

        logs = get_log_files()
        target = sys.argv[2]

        if target == "logs":
            run_remove_logs()

        elif target in logs and len(sys.argv) > 3 and sys.argv[3].isdigit():
            remove_oldest_lines(logs[target], int(sys.argv[3]))
            ok(f"Removed {sys.argv[3]} oldest lines from {target}")
            log_file(f"Removed {sys.argv[3]} oldest lines from {target}")

        elif target in logs:
            truncate_log(logs[target])
            ok(f"{target} cleared")
            log_file(f"{target} truncated")

        else:
            handle_remove_command(sys.argv)

        return

    if CMD == "update":
        run_update()
        return

    if CMD == "uninstall":
        uninstall_all()
        return

    if CMD == "log":
        run_log_command()
        return

    if CMD == "config":
        run_config_command()
        return

    if CMD == "supported":
        if SUB:
            check_supported(SUB)
        else:
            list_supported()
        return

    if CMD == "host":
        run_host_command()
        return

    usage()

if __name__ == "__main__":
    main()
