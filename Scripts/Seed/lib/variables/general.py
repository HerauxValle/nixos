"""
lib/variables/general.py — all global constants, single source of truth
"""

import os

# ── project root ──────────────────────────────────────────────────────────────

PROJECT_ROOT   = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROJECT_CONFIG = os.path.join(PROJECT_ROOT, "config")
PROJECT_HELP   = os.path.join(PROJECT_ROOT, "help")

# ── runtime / temp paths ──────────────────────────────────────────────────────

TMP_BASE      = "/tmp/simpleDocker"
MNT_BASE      = f"{TMP_BASE}/mnt"
SESSIONS_BASE = f"{TMP_BASE}/sessions"

# ── img encryption ────────────────────────────────────────────────────────────

LUKS_DEFAULT_KEY = "sd_default_key_0"
LUKS_ITER_TIME   = 1                    # ms — fast for dev, increase for prod

# ── img folder structure (created on sd create/select) ───────────────────────

IMG_FOLDERS = [
    "blueprints",
    "containers",
    "profiles",
    "layers",
    "formats",
    "help",
    "config",
    "logs",
    "rootfs_cache",
    ".tmp",
    ".tmp/processes",
    ".tmp/tables",
    ".cache",
]

IMG_DYNAMIC_DIRS = [".cache", ".tmp/tables"]  # created by regenerate_missing too

# ── img subdir names (used as relative paths inside mnt) ─────────────────────

DIR_BLUEPRINTS  = "blueprints"
DIR_CONTAINERS  = "containers"
DIR_PROFILES    = "profiles"
DIR_LAYERS      = "layers"
DIR_FORMATS     = "formats"
DIR_CONFIG      = "config"
DIR_LOGS        = "logs"
DIR_ROOTFS      = "rootfs_cache"
DIR_CACHE       = ".cache"
DIR_TMP         = ".tmp"
DIR_PROCESSES   = ".tmp/processes"
DIR_TABLES      = ".tmp/tables"
DIR_TRASH       = ".trash"

# ── img file names ────────────────────────────────────────────────────────────

FILE_META       = "meta.toml"
FILE_OUTPUT_LOG = "output.log"
FILE_SETTINGS   = ".cache/settings.json"
FILE_SD_INIT    = "/.sd_init.sh"

# ── img auto-size candidates (MiB, tried in order) ───────────────────────────

AUTO_SIZES_MIB = [51200, 25600, 10240, 5120]

# ── layer / container constants ───────────────────────────────────────────────

MASKED_PATHS = [
    "/proc/acpi", "/proc/kcore", "/proc/keys",
    "/proc/latency_stats", "/proc/timer_list",
    "/proc/sched_debug", "/sys/firmware",
]

# ── sd binary file format ─────────────────────────────────────────────────────

SD_MAGIC   = b"SD\x01\x02"
SD_VERSION = "1.0"

# ── config / shebang ─────────────────────────────────────────────────────────

KNOWN_SHEBANGS = {"defaults", "distros", "ruleset", "rules", "encryption-presets"}

# ── editor fallbacks ──────────────────────────────────────────────────────────

EDITOR_FALLBACKS = ["nano", "vim", "nvim", "vi"]

# ── terminal emulator names (for session key detection) ───────────────────────

TERMINAL_NAMES = {
    "kitty", "alacritty", "wezterm", "wezterm-gui",
    "gnome-terminal", "konsole", "xterm", "urxvt", "st",
    "foot", "tilix", "terminator", "xfce4-terminal",
    "lxterminal", "mate-terminal", "hyper", "tmux",
    "screen", "sshd", "login",
}

# ── rootfs / package managers ─────────────────────────────────────────────────

PKG_MANAGERS = [
    ("apt-get",  "/usr/bin/apt-get",  "apt"),
    ("apt",      "/usr/bin/apt",      "apt"),
    ("pacman",   "/usr/bin/pacman",   "pacman"),
    ("apk",      "/sbin/apk",         "apk"),
    ("dnf",      "/usr/bin/dnf",      "dnf"),
    ("yum",      "/usr/bin/yum",      "yum"),
    ("zypper",   "/usr/bin/zypper",   "zypper"),
]

ROOTFS_CACHE_SUBDIR = "rootfs_cache"

# ── output / table ────────────────────────────────────────────────────────────

TABLE_SECTION_KEY = "__section__"

# ── output modes ─────────────────────────────────────────────────────────────

MODE_TABLE   = "table"
MODE_VERBOSE = "verbose"
VALID_MODES  = (MODE_TABLE, MODE_VERBOSE, "json")

# ── cli flag → mode mapping ───────────────────────────────────────────────────

MODE_FLAGS = {"-t": MODE_TABLE, "-n": MODE_VERBOSE}
DEBUG_FLAG = "-d"

# ── default select search depth ───────────────────────────────────────────────

DEFAULT_SEARCH_DEPTH = 3

# ── blueprint ─────────────────────────────────────────────────────────────────

DEFAULT_BLUEPRINT_EXT = ".sdc"

# ── img header system ─────────────────────────────────────────────────────────

IMG_HEADER_MAGIC   = b"SDIMG\x01\x02"  # 7 bytes
IMG_HEADER_VERSION = 1                  # uint8
IMG_HEADER_SIZE    = 4096               # bytes (total header block size)
IMG_HEADER_OFFSET  = 1048576            # bytes (1MB, after LUKS naturally reserves ~1MB)
IMG_SCAN_DEPTH     = 5                  # max directory depth when scanning $HOME
IMG_ENV_VAR        = "SD_IMG"           # power-user override

# ── luks slot layout ───────────────────────────────────────────────────────────

SLOT_HARDCODED = 0      # weak hardcoded passkey (development/fallback)
SLOT_KEYFILE_A = 1      # internal keyfile A (auth for operations)
SLOT_KEYFILE_B = 2      # internal keyfile B (backup during rotation)

# ── unlock priority (order of attempts when opening img) ──────────────────────

UNLOCK_PRIORITY = ["hardcoded", "keyfile_a", "derived", "passkey"]