#!/usr/bin/env bash
# info.sh -- exhaustive, machine-parsable system report. 124 fields
# across 15 categories. The bar for a field existing here is: (a) you
# cannot get it from one short obvious command, and (b) it's actually
# useful (capacity planning, drift/health checks, security posture),
# not just "because it exists". Cheap fields (uname, readlink) sit next
# to genuinely expensive ones (full closure walks, nix evals against
# the flake, per-package size sorts) -- see the laziness note below.
#
# Each field is its own case arm in field_value(), computed lazily --
# only fields actually selected get run, so `-o` for a handful of cheap
# fields stays fast even though a full default run legitimately takes
# several seconds (multiple nix eval calls, a full closure walk, a
# store-wide dedup scan). That's the tradeoff for depth over speed here.
#
# Output modes (mirrors lsblk's -o/-n/-P):
#   default        grouped "LABEL: value" report, all fields
#   -o F1,F2,...   select/order fields (case-insensitive), `-o list` to
#                  print available field names, grouped, with
#                  descriptions
#   -n             values only, no labels -- one per line, in -o order,
#                  e.g. `pacnix info -o STORE_SIZE -n` for a single clean
#                  value to pipe into sort/cut/whatever
#   -p             KEY="value" pairs, one per line -- eval-able in bash,
#                  trivially regex-parsable elsewhere
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"

FLAKE_REF="$FLAKE#nixosConfigurations.$HOST.config"

# name:category pairs, in display order
field_order=(
    PKGS_SYSTEM:Packages PKGS_HOME:Packages PKGS_IMPERATIVE:Packages
    PKGS_DECLARED_TOTAL:Packages CLOSURE_PACKAGES:Packages

    STORE_SIZE:Store STORE_PATHS:Store STORE_DERIVATIONS:Store
    STORE_OUTPUTS:Store STORE_DUPES:Store STORE_FOD_COUNT:Store
    STORE_TOP5_LARGEST:Store STORE_TOP5_DUPLICATED:Store
    CLOSURE_SIZE:Store NIX_DB_SIZE:Store

    GENERATIONS:Generations CURRENT_GEN:Generations GEN_AGE:Generations
    OLDEST_GEN_AGE:Generations GEN_AVG_INTERVAL:Generations GRUB_ENTRIES:Generations

    FLAKE_INPUTS:Flake FLAKE_INPUT_NAMES:Flake NIXPKGS_REV:Flake
    NIXPKGS_DATE:Flake FLAKE_LOCK_AGE:Flake CONFIG_MODULES:Flake
    CONFIG_LOC:Flake CONFIG_TODOS:Flake CONFIG_OVERLAYS:Flake
    CONFIG_LARGEST_FILE:Flake STATE_VERSION:Flake KERNEL_PACKAGE_VERSION:Flake

    NIXOS_VERSION:System KERNEL:System HOST:System NIX_VERSION:System
    UPTIME:System BOOT_TIME:System KERNEL_MODULES:System
    SYSTEMD_UNITS:System SYSTEMD_ENABLED:System SYSTEMD_FAILED:System
    SYSTEMD_STATE:System SYSTEMD_TIMERS:System SYSTEMD_SOCKETS:System
    NIX_DAEMON_STATUS:System GCROOTS:System COREDUMPS:System

    DISK_FREE:Disk DISK_USED_PCT:Disk NIX_FS:Disk INODE_USAGE:Disk
    MOUNTED_FS_COUNT:Disk SWAP_TOTAL:Disk SWAP_USED:Disk SWAP_DEVICES:Disk
    LUKS_VOLUMES:Disk STORAGE_DEVICES:Disk

    BTRFS_ALLOCATED:Btrfs BTRFS_UNALLOCATED:Btrfs BTRFS_DEVICE_SIZE:Btrfs
    BTRFS_DATA_RATIO:Btrfs BTRFS_METADATA_RATIO:Btrfs
    BTRFS_GLOBAL_RESERVE:Btrfs BTRFS_SUBVOLUMES:Btrfs

    NIX_MAX_JOBS:NixConfig NIX_CORES:NixConfig NIX_SANDBOX:NixConfig
    NIX_SUBSTITUTERS:NixConfig NIX_SUBSTITUTER_NAMES:NixConfig
    NIX_TRUSTED_USERS:NixConfig NIX_EXPERIMENTAL_FEATURES:NixConfig
    NIX_AUTO_OPTIMISE:NixConfig NIX_KEEP_OUTPUTS:NixConfig
    NIX_KEEP_DERIVATIONS:NixConfig NIX_MIN_FREE:NixConfig
    NIX_MAX_FREE:NixConfig NIX_BUILD_USERS:NixConfig

    GC_AUTOMATIC:GC GC_SCHEDULE:GC GC_PERSISTENT:GC GC_LAST_RUN:GC

    CPU_MODEL:Hardware CPU_ARCH:Hardware CPU_CORES:Hardware
    CPU_THREADS:Hardware CPU_MAX_MHZ:Hardware MEM_TOTAL:Hardware
    MEM_USED:Hardware MEM_AVAILABLE:Hardware LOAD_AVG:Hardware GPU_MODEL:Hardware

    BOOTLOADER:Boot SECURE_BOOT:Boot TPM2_SUPPORT:Boot VIRTUALIZATION:Boot
    KERNEL_PARAMS_COUNT:Boot KERNEL_CMDLINE:Boot BOOT_KERNELS_SIZE:Boot ESP_FREE:Boot

    NET_INTERFACES:Network NET_PRIMARY_IP:Network NET_GATEWAY:Network
    NET_DNS:Network NET_LISTENING_PORTS:Network NET_MANAGER:Network FIREWALL_ENABLED:Network

    SSH_KEYS_COUNT:Security SUDO_KEYFILE_ACTIVE:Security WHEEL_USERS:Security
    USER_ACCOUNTS:Security LAST_LOGIN:Security

    JOURNAL_SIZE:Health JOURNAL_ERRORS_24H:Health JOURNAL_WARNINGS_24H:Health
    JOURNAL_BOOTS:Health PROCESS_COUNT:Health ZOMBIE_COUNT:Health

    DESKTOP:Session SESSION_TYPE:Session LOCALE:Session TIMEZONE:Session SHELL_DEFAULT:Session
)
field_names=()
for entry in "${field_order[@]}"; do field_names+=("${entry%%:*}"); done

field_category() {
    for entry in "${field_order[@]}"; do
        [ "${entry%%:*}" = "$1" ] && { echo "${entry##*:}"; return; }
    done
}

field_desc() {
    case "$1" in
        PKGS_SYSTEM) echo "packages on the system PATH from environment.systemPackages (/run/current-system/sw)" ;;
        PKGS_HOME) echo "packages from home-manager's home.packages (per-user home-manager-path)" ;;
        PKGS_IMPERATIVE) echo "packages installed outside the flake via nix-env/nix profile -- non-zero means the system isn't fully declarative" ;;
        PKGS_DECLARED_TOTAL) echo "PKGS_SYSTEM + PKGS_HOME + PKGS_IMPERATIVE -- everything explicitly asked for, not counting transitive deps" ;;
        CLOSURE_PACKAGES) echo "full transitive closure path count for the running system -- everything actually needed to run it" ;;
        STORE_SIZE) echo "on-disk size of the whole /nix/store -- every generation, every build dependency" ;;
        STORE_PATHS) echo "top-level path count in /nix/store (derivations + built outputs)" ;;
        STORE_DERIVATIONS) echo "*.drv files in /nix/store -- build recipes, not build products" ;;
        STORE_OUTPUTS) echo "STORE_PATHS minus STORE_DERIVATIONS -- actual built packages/outputs present" ;;
        STORE_DUPES) echo "output basenames (not .drv, not per-generation system closures) with >1 version present -- real dedup candidates" ;;
        STORE_FOD_COUNT) echo "fixed-output derivations in the store -- network-fetched sources (tarballs, git checkouts) rather than built from other derivations" ;;
        STORE_TOP5_LARGEST) echo "5 biggest packages directly in the system closure, by their own size (not counting their deps)" ;;
        STORE_TOP5_DUPLICATED) echo "5 output basenames with the most simultaneous versions in the store, and how many" ;;
        CLOSURE_SIZE) echo "on-disk size of just the running system's closure (/run/current-system)" ;;
        NIX_DB_SIZE) echo "size of the Nix store registration database (/nix/var/nix/db)" ;;
        GENERATIONS) echo "total system generations kept (/nix/var/nix/profiles/system-*-link)" ;;
        CURRENT_GEN) echo "generation number currently booted" ;;
        GEN_AGE) echo "time since the current generation was created" ;;
        OLDEST_GEN_AGE) echo "time since the oldest kept generation was created" ;;
        GEN_AVG_INTERVAL) echo "OLDEST_GEN_AGE / GENERATIONS -- roughly how often you rebuild" ;;
        GRUB_ENTRIES) echo "menu entries actually in grub.cfg right now, capped by boot.loader.grub.configurationLimit" ;;
        FLAKE_INPUTS) echo "direct inputs declared in flake.nix (root node of flake.lock, not transitive/follows)" ;;
        FLAKE_INPUT_NAMES) echo "names of the direct flake inputs" ;;
        NIXPKGS_REV) echo "locked nixpkgs commit (short rev) this system is pinned to" ;;
        NIXPKGS_DATE) echo "commit date of the locked nixpkgs revision" ;;
        FLAKE_LOCK_AGE) echo "time since flake.lock was last updated" ;;
        CONFIG_MODULES) echo "*.nix file count under the Nixos/ config tree" ;;
        CONFIG_LOC) echo "total lines across all *.nix files under Nixos/" ;;
        CONFIG_TODOS) echo "TODO/FIXME/XXX markers across the Nixos/ config tree" ;;
        CONFIG_OVERLAYS) echo "*.nix files under Nixos/ that define an overlay" ;;
        CONFIG_LARGEST_FILE) echo "biggest *.nix file under Nixos/ by line count" ;;
        STATE_VERSION) echo "system.stateVersion pinned in the config -- the NixOS release your on-disk data formats were created for" ;;
        KERNEL_PACKAGE_VERSION) echo "kernel version the config selects (boot.kernelPackages) -- compare to KERNEL for reboot-pending drift" ;;
        NIXOS_VERSION) echo "nixos-version string (release, codename)" ;;
        KERNEL) echo "running kernel release (uname -r)" ;;
        HOST) echo "flake hostname this system was built as" ;;
        NIX_VERSION) echo "nix package manager version" ;;
        UPTIME) echo "time since last boot" ;;
        BOOT_TIME) echo "last boot's total startup time (systemd-analyze time)" ;;
        KERNEL_MODULES) echo "currently loaded kernel modules (lsmod)" ;;
        SYSTEMD_UNITS) echo "total systemd units currently loaded" ;;
        SYSTEMD_ENABLED) echo "systemd unit files enabled at boot" ;;
        SYSTEMD_FAILED) echo "systemd units currently in a failed state -- should be 0" ;;
        SYSTEMD_STATE) echo "systemctl is-system-running -- overall systemd health summary" ;;
        SYSTEMD_TIMERS) echo "active systemd timers" ;;
        SYSTEMD_SOCKETS) echo "active systemd sockets" ;;
        NIX_DAEMON_STATUS) echo "nix-daemon.service active state" ;;
        GCROOTS) echo "registered GC roots -- anything reachable from these survives nix-collect-garbage" ;;
        COREDUMPS) echo "coredumps on record (coredumpctl list)" ;;
        DISK_FREE) echo "free space on the filesystem backing /nix" ;;
        DISK_USED_PCT) echo "used% on the filesystem backing /nix" ;;
        NIX_FS) echo "filesystem type and source device backing /nix" ;;
        INODE_USAGE) echo "inode usage% on / (btrfs reports \"-\": it allocates inodes dynamically, no fixed count)" ;;
        MOUNTED_FS_COUNT) echo "currently mounted filesystems (findmnt)" ;;
        SWAP_TOTAL) echo "total configured swap" ;;
        SWAP_USED) echo "swap currently in use" ;;
        SWAP_DEVICES) echo "active swap devices/files" ;;
        LUKS_VOLUMES) echo "block devices currently unlocked as crypto_LUKS (lsblk) -- includes root if it's LUKS-backed" ;;
        STORAGE_DEVICES) echo "physical/virtual disks visible to the system, with size" ;;
        BTRFS_ALLOCATED) echo "space btrfs has claimed from the device into chunks (can exceed actual data written)" ;;
        BTRFS_UNALLOCATED) echo "raw device space not yet claimed into any btrfs chunk" ;;
        BTRFS_DEVICE_SIZE) echo "total btrfs device size backing /nix" ;;
        BTRFS_DATA_RATIO) echo "btrfs data replication ratio (1.0 = single, 2.0 = DUP/RAID1)" ;;
        BTRFS_METADATA_RATIO) echo "btrfs metadata replication ratio" ;;
        BTRFS_GLOBAL_RESERVE) echo "btrfs's reserved emergency allocation headroom" ;;
        BTRFS_SUBVOLUMES) echo "btrfs subvolume count on / -- needs root, shows n/a otherwise" ;;
        NIX_MAX_JOBS) echo "nix.conf max-jobs -- concurrent derivation builds allowed" ;;
        NIX_CORES) echo "nix.conf cores -- cores per build (0 = use all)" ;;
        NIX_SANDBOX) echo "nix.conf sandbox -- whether builds run sandboxed" ;;
        NIX_SUBSTITUTERS) echo "configured binary cache count" ;;
        NIX_SUBSTITUTER_NAMES) echo "configured binary cache URLs" ;;
        NIX_TRUSTED_USERS) echo "users allowed to override nix daemon settings / use untrusted substituters" ;;
        NIX_EXPERIMENTAL_FEATURES) echo "enabled experimental Nix features (e.g. flakes)" ;;
        NIX_AUTO_OPTIMISE) echo "nix.conf auto-optimise-store -- hardlink dedup on every build, not just manual `pacnix optimise`" ;;
        NIX_KEEP_OUTPUTS) echo "nix.conf keep-outputs -- keep build outputs of derivations that are GC roots" ;;
        NIX_KEEP_DERIVATIONS) echo "nix.conf keep-derivations -- keep .drv files for installed paths" ;;
        NIX_MIN_FREE) echo "nix.conf min-free -- free space threshold that triggers automatic GC during builds (0 = disabled)" ;;
        NIX_MAX_FREE) echo "nix.conf max-free -- free space target automatic GC stops at" ;;
        NIX_BUILD_USERS) echo "nixbld* sandbox build user accounts provisioned" ;;
        GC_AUTOMATIC) echo "nix.gc.automatic -- whether scheduled GC is configured" ;;
        GC_SCHEDULE) echo "nix.gc.dates -- when scheduled GC runs" ;;
        GC_PERSISTENT) echo "nix.gc.persistent -- whether a missed scheduled GC runs on next boot" ;;
        GC_LAST_RUN) echo "timestamp nix-gc.service last actually ran (journalctl)" ;;
        CPU_MODEL) echo "CPU model name" ;;
        CPU_ARCH) echo "CPU architecture (uname -m)" ;;
        CPU_CORES) echo "physical CPU cores" ;;
        CPU_THREADS) echo "logical CPU threads (cores x SMT)" ;;
        CPU_MAX_MHZ) echo "max CPU clock speed" ;;
        MEM_TOTAL) echo "total physical RAM" ;;
        MEM_USED) echo "RAM currently in use" ;;
        MEM_AVAILABLE) echo "RAM available for new allocations without swapping (includes reclaimable cache)" ;;
        LOAD_AVG) echo "1/5/15-minute load average" ;;
        GPU_MODEL) echo "primary GPU (lspci VGA/3D controller)" ;;
        BOOTLOADER) echo "detected bootloader (grub.cfg present vs systemd-boot ESP entries)" ;;
        SECURE_BOOT) echo "Secure Boot state (bootctl status)" ;;
        TPM2_SUPPORT) echo "whether a TPM2 device node is present (/dev/tpm0) -- what the sudo-keyfile PAM module can rely on" ;;
        VIRTUALIZATION) echo "systemd-detect-virt -- \"none\" means bare metal" ;;
        KERNEL_PARAMS_COUNT) echo "word count of the active kernel command line (/proc/cmdline)" ;;
        KERNEL_CMDLINE) echo "the active kernel command line, verbatim" ;;
        BOOT_KERNELS_SIZE) echo "size of /boot/kernels -- GRUB's copy of kernel+initrd per generation, separate from /nix/store" ;;
        ESP_FREE) echo "free space on /boot (EFI system partition)" ;;
        NET_INTERFACES) echo "network interfaces present, excluding loopback" ;;
        NET_PRIMARY_IP) echo "primary IPv4 address (first global-scope interface)" ;;
        NET_GATEWAY) echo "default route gateway" ;;
        NET_DNS) echo "nameservers in effect (/etc/resolv.conf)" ;;
        NET_LISTENING_PORTS) echo "TCP sockets in LISTEN state" ;;
        NET_MANAGER) echo "which network manager is active: NetworkManager or systemd-networkd" ;;
        FIREWALL_ENABLED) echo "networking.firewall.enable as configured in the flake" ;;
        SSH_KEYS_COUNT) echo "public keys in ~/.ssh" ;;
        SUDO_KEYFILE_ACTIVE) echo "whether the keyfile-based passwordless sudo PAM rule is enabled in the config" ;;
        WHEEL_USERS) echo "members of the wheel (sudo-capable) group" ;;
        USER_ACCOUNTS) echo "real human user accounts (uid 1000-29999, excludes nixbld build users)" ;;
        LAST_LOGIN) echo "most recent login session (last -1)" ;;
        JOURNAL_SIZE) echo "disk space used by the systemd journal" ;;
        JOURNAL_ERRORS_24H) echo "journal entries at error level or worse in the last 24h" ;;
        JOURNAL_WARNINGS_24H) echo "journal entries at warning level in the last 24h" ;;
        JOURNAL_BOOTS) echo "boots the journal has records for" ;;
        PROCESS_COUNT) echo "currently running processes (ps -e)" ;;
        ZOMBIE_COUNT) echo "processes in zombie state -- should be 0" ;;
        DESKTOP) echo "current desktop session (\$XDG_CURRENT_DESKTOP)" ;;
        SESSION_TYPE) echo "Wayland or X11 (\$XDG_SESSION_TYPE)" ;;
        LOCALE) echo "active locale (\$LANG)" ;;
        TIMEZONE) echo "configured system timezone" ;;
        SHELL_DEFAULT) echo "your login shell (\$SHELL)" ;;
        *) echo "" ;;
    esac
}

human_duration() {
    local s=$1 d h m
    d=$((s / 86400)); h=$(((s % 86400) / 3600)); m=$(((s % 3600) / 60))
    if [ "$d" -gt 0 ]; then printf "%dd %dh" "$d" "$h"
    elif [ "$h" -gt 0 ]; then printf "%dh %dm" "$h" "$m"
    else printf "%dm" "$m"
    fi
}

# One nix show-config call per field that needs it -- ~25ms each, cheap
# enough that per-field independence (no shared cache) isn't worth the
# complexity, matching every other field's fully lazy, standalone design.
nix_conf() { nix show-config 2>/dev/null | awk -F' = ' -v k="$1" '$1==k{print $2}'; }

# Every arm below is best-effort and ends in `|| true`: with pipefail on,
# a pipe like `grep pattern | wc -l` still reports the *grep* stage's
# exit code (1 on zero matches) even though wc -l already printed the
# correct "0" -- set -e would treat that as this one field failing and
# kill the whole report. The `|| true` launders the exit status only;
# stdout already produced by the pipeline is unaffected. Anything that
# needs a tool that might not be installed (bootctl, coredumpctl, ...)
# checks `command -v` first and reports "n/a" instead of erroring.
field_value() {
    case "$1" in
        PKGS_SYSTEM) nix-store -q --references /run/current-system/sw 2>/dev/null | wc -l || true ;;
        PKGS_HOME)
            hm_path="$(nix-store -q --references "/etc/profiles/per-user/${USER:-$(id -un)}" 2>/dev/null | grep -m1 'home-manager-path' || true)"
            [ -n "$hm_path" ] && { nix-store -q --references "$hm_path" 2>/dev/null | wc -l || true; } || echo 0
            ;;
        PKGS_IMPERATIVE) nix-env -q 2>/dev/null | wc -l || true ;;
        PKGS_DECLARED_TOTAL)
            echo $(( $(field_value PKGS_SYSTEM) + $(field_value PKGS_HOME) + $(field_value PKGS_IMPERATIVE) ))
            ;;
        CLOSURE_PACKAGES) nix-store -q --requisites /run/current-system 2>/dev/null | wc -l || true ;;

        STORE_SIZE) du -sh /nix/store 2>/dev/null | cut -f1 || true ;;
        STORE_PATHS) ls /nix/store 2>/dev/null | wc -l || true ;;
        STORE_DERIVATIONS) find /nix/store -maxdepth 1 -name '*.drv' 2>/dev/null | wc -l || true ;;
        STORE_OUTPUTS)
            echo $(( $(field_value STORE_PATHS) - $(field_value STORE_DERIVATIONS) ))
            ;;
        STORE_DUPES)
            ls /nix/store 2>/dev/null \
                | grep -E '^[a-z0-9]{32}-' | grep -v '\.drv$' | grep -v '^[a-z0-9]\{32\}-nixos-system-' \
                | sed -E 's/^[a-z0-9]{32}-//; s/-[0-9][0-9a-zA-Z.+_-]*$//' \
                | sort | uniq -c | awk '$1>1' | wc -l || true
            ;;
        STORE_FOD_COUNT) grep -l 'outputHash' /nix/store/*.drv 2>/dev/null | wc -l || true ;;
        STORE_TOP5_LARGEST)
            nix path-info -S $(nix-store -q --references /run/current-system/sw 2>/dev/null) 2>/dev/null \
                | sort -k2 -rn | head -5 \
                | while read -r path bytes; do
                    name="${path##*/}"; name="${name#*-}"
                    printf "%s (%s), " "$name" "$(numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "$bytes")"
                  done | sed 's/, $//' || true
            ;;
        STORE_TOP5_DUPLICATED)
            ls /nix/store 2>/dev/null \
                | grep -E '^[a-z0-9]{32}-' | grep -v '\.drv$' | grep -v '^[a-z0-9]\{32\}-nixos-system-' \
                | sed -E 's/^[a-z0-9]{32}-//; s/-[0-9][0-9a-zA-Z.+_-]*$//' \
                | sort | uniq -c | sort -rn | awk '$1>1' | head -5 \
                | awk '{printf "%s (%s), ", $2, $1}' | sed 's/, $//' || true
            ;;
        CLOSURE_SIZE) nix path-info -Sh /run/current-system 2>/dev/null | awk '{print $2, $3}' || true ;;
        NIX_DB_SIZE) du -sh /nix/var/nix/db 2>/dev/null | cut -f1 || true ;;

        GENERATIONS) ls /nix/var/nix/profiles 2>/dev/null | grep -E '^system-[0-9]+-link$' | wc -l || true ;;
        CURRENT_GEN) readlink /nix/var/nix/profiles/system 2>/dev/null | grep -oE '[0-9]+' || echo "?" ;;
        GEN_AGE)
            mtime="$(stat -c '%Y' /nix/var/nix/profiles/system 2>/dev/null || true)"
            [ -n "$mtime" ] && human_duration "$(($(date +%s) - mtime))" || echo "?"
            ;;
        OLDEST_GEN_AGE)
            oldest="$( (stat -c '%Y' /nix/var/nix/profiles/system-*-link 2>/dev/null || true) | sort -n | head -1)"
            [ -n "$oldest" ] && human_duration "$(($(date +%s) - oldest))" || echo "?"
            ;;
        GEN_AVG_INTERVAL)
            oldest="$( (stat -c '%Y' /nix/var/nix/profiles/system-*-link 2>/dev/null || true) | sort -n | head -1)"
            gens="$(field_value GENERATIONS)"
            if [ -n "$oldest" ] && [ "$gens" -gt 1 ]; then
                human_duration "$((($(date +%s) - oldest) / (gens - 1)))"
            else
                echo "?"
            fi
            ;;
        GRUB_ENTRIES) grep '^menuentry' /boot/grub/grub.cfg 2>/dev/null | wc -l || true ;;

        FLAKE_INPUTS) python3 -c "import json;print(len(json.load(open('$FLAKE/flake.lock'))['nodes']['root']['inputs']))" 2>/dev/null || echo "?" ;;
        FLAKE_INPUT_NAMES) python3 -c "import json;print(', '.join(json.load(open('$FLAKE/flake.lock'))['nodes']['root']['inputs'].keys()))" 2>/dev/null || echo "?" ;;
        NIXPKGS_REV) python3 -c "import json;print(json.load(open('$FLAKE/flake.lock'))['nodes']['nixpkgs']['locked'].get('rev','?')[:12])" 2>/dev/null || echo "?" ;;
        NIXPKGS_DATE) python3 -c "
import json, datetime
d = json.load(open('$FLAKE/flake.lock'))['nodes']['nixpkgs']['locked']
print(datetime.datetime.fromtimestamp(d['lastModified'], datetime.timezone.utc).strftime('%Y-%m-%d'))
" 2>/dev/null || echo "?" ;;
        FLAKE_LOCK_AGE)
            mtime="$(stat -c '%Y' "$FLAKE/flake.lock" 2>/dev/null || true)"
            [ -n "$mtime" ] && human_duration "$(($(date +%s) - mtime))" || echo "?"
            ;;
        CONFIG_MODULES) find "$FLAKE/Nixos" -name '*.nix' 2>/dev/null | wc -l || true ;;
        CONFIG_LOC) find "$FLAKE/Nixos" -name '*.nix' -exec cat {} + 2>/dev/null | wc -l || true ;;
        CONFIG_TODOS) grep -rEc "TODO|FIXME|XXX" "$FLAKE/Nixos" --include='*.nix' 2>/dev/null | awk -F: '{s+=$2} END{print s+0}' || true ;;
        CONFIG_OVERLAYS) grep -rl 'overlays *=' "$FLAKE/Nixos" --include='*.nix' 2>/dev/null | wc -l || true ;;
        CONFIG_LARGEST_FILE)
            find "$FLAKE/Nixos" -name '*.nix' -exec wc -l {} \; 2>/dev/null \
                | sort -rn | head -1 | awk '{print $2, "("$1" lines)"}' || true
            ;;
        STATE_VERSION) timeout 10 nix eval --raw "$FLAKE_REF.system.stateVersion" 2>/dev/null || echo "?" ;;
        KERNEL_PACKAGE_VERSION) timeout 10 nix eval --raw "$FLAKE_REF.boot.kernelPackages.kernel.version" 2>/dev/null || echo "?" ;;

        NIXOS_VERSION) nixos-version 2>/dev/null || true ;;
        KERNEL) uname -r ;;
        HOST) echo "$HOST" ;;
        NIX_VERSION) nix --version 2>/dev/null | awk '{print $3}' || true ;;
        UPTIME) uptime -p 2>/dev/null || true ;;
        BOOT_TIME) systemd-analyze time 2>/dev/null | grep -oE '[0-9.]+s *$' | tr -d ' ' || true ;;
        KERNEL_MODULES) lsmod 2>/dev/null | tail -n +2 | wc -l || true ;;
        SYSTEMD_UNITS) systemctl list-units --all --no-legend 2>/dev/null | wc -l || true ;;
        SYSTEMD_ENABLED) systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | wc -l || true ;;
        SYSTEMD_FAILED) systemctl --failed --no-legend 2>/dev/null | wc -l || true ;;
        SYSTEMD_STATE) systemctl is-system-running 2>/dev/null || true ;;
        SYSTEMD_TIMERS) systemctl list-timers --all --no-legend 2>/dev/null | wc -l || true ;;
        SYSTEMD_SOCKETS) systemctl list-sockets --all --no-legend 2>/dev/null | wc -l || true ;;
        NIX_DAEMON_STATUS) systemctl is-active nix-daemon.service 2>/dev/null || true ;;
        GCROOTS) find /nix/var/nix/gcroots -maxdepth 3 2>/dev/null | wc -l || true ;;
        COREDUMPS) command -v coredumpctl >/dev/null 2>&1 && { coredumpctl list --no-pager 2>/dev/null | tail -n +2 | wc -l || true; } || echo "n/a (coredumpctl not installed)" ;;

        DISK_FREE) df -h /nix 2>/dev/null | awk 'NR==2{print $4}' || true ;;
        DISK_USED_PCT) df -h /nix 2>/dev/null | awk 'NR==2{print $5}' || true ;;
        NIX_FS) findmnt -no FSTYPE,SOURCE /nix 2>/dev/null || true ;;
        INODE_USAGE) df -i / 2>/dev/null | awk 'NR==2{print $5}' || true ;;
        MOUNTED_FS_COUNT) findmnt -rn 2>/dev/null | wc -l || true ;;
        SWAP_TOTAL) free -h 2>/dev/null | awk '/^Swap:/{print $2}' || true ;;
        SWAP_USED) free -h 2>/dev/null | awk '/^Swap:/{print $3}' || true ;;
        SWAP_DEVICES) swapon --show=NAME --noheadings 2>/dev/null | wc -l || true ;;
        LUKS_VOLUMES) lsblk -o FSTYPE 2>/dev/null | grep -c crypto_LUKS || true ;;
        STORAGE_DEVICES) lsblk -d -no NAME,SIZE 2>/dev/null | awk '{printf "%s (%s), ", $1, $2}' | sed 's/, $//' || true ;;

        BTRFS_ALLOCATED) btrfs filesystem usage -T / 2>/dev/null | awk -F': *\t*' '/Device allocated/{print $2; exit}' | xargs || true ;;
        BTRFS_UNALLOCATED) btrfs filesystem usage -T / 2>/dev/null | awk -F': *\t*' '/Device unallocated/{print $2; exit}' | xargs || true ;;
        BTRFS_DEVICE_SIZE) btrfs filesystem usage -T / 2>/dev/null | awk -F': *\t*' '/Device size/{print $2; exit}' | xargs || true ;;
        BTRFS_DATA_RATIO) btrfs filesystem usage -T / 2>/dev/null | awk -F': *\t*' '/Data ratio/{print $2; exit}' | xargs || true ;;
        BTRFS_METADATA_RATIO) btrfs filesystem usage -T / 2>/dev/null | awk -F': *\t*' '/Metadata ratio/{print $2; exit}' | xargs || true ;;
        BTRFS_GLOBAL_RESERVE) btrfs filesystem usage -T / 2>/dev/null | awk -F': *\t*' '/Global reserve/{print $2; exit}' | xargs | awk '{print $1}' || true ;;
        BTRFS_SUBVOLUMES)
            out="$(btrfs subvolume list / 2>/dev/null)"
            [ -n "$out" ] && echo "$out" | wc -l || echo "n/a (needs root)"
            ;;

        NIX_MAX_JOBS) nix_conf "max-jobs" ;;
        NIX_CORES) nix_conf "cores" ;;
        NIX_SANDBOX) nix_conf "sandbox" ;;
        NIX_SUBSTITUTERS) nix_conf "substituters" | wc -w || true ;;
        NIX_SUBSTITUTER_NAMES) nix_conf "substituters" | tr ' ' ',' ;;
        NIX_TRUSTED_USERS) nix_conf "trusted-users" ;;
        NIX_EXPERIMENTAL_FEATURES) nix_conf "experimental-features" | tr ' ' ',' ;;
        NIX_AUTO_OPTIMISE) nix_conf "auto-optimise-store" ;;
        NIX_KEEP_OUTPUTS) nix_conf "keep-outputs" ;;
        NIX_KEEP_DERIVATIONS) nix_conf "keep-derivations" ;;
        NIX_MIN_FREE) nix_conf "min-free" ;;
        NIX_MAX_FREE) nix_conf "max-free" ;;
        NIX_BUILD_USERS) awk -F: '$1 ~ /^nixbld/' /etc/passwd 2>/dev/null | wc -l || true ;;

        GC_AUTOMATIC) timeout 10 nix eval "$FLAKE_REF.nix.gc.automatic" 2>/dev/null || echo "?" ;;
        GC_SCHEDULE) timeout 10 nix eval "$FLAKE_REF.nix.gc.dates" 2>/dev/null | tr -d '[]"' | xargs || echo "?" ;;
        GC_PERSISTENT) timeout 10 nix eval "$FLAKE_REF.nix.gc.persistent" 2>/dev/null || echo "?" ;;
        GC_LAST_RUN) journalctl -u nix-gc.service --no-pager -n1 --output=short-iso 2>/dev/null | awk '{print $1}' || echo "n/a (never run, or no journal record)" ;;

        CPU_MODEL) lscpu 2>/dev/null | awk -F': +' '/^Model name/{print $2; exit}' || true ;;
        CPU_ARCH) uname -m ;;
        CPU_CORES)
            cps="$(lscpu 2>/dev/null | awk -F': +' '/Core\(s\) per socket/{print $2; exit}')"
            sockets="$(lscpu 2>/dev/null | awk -F': +' '/^Socket\(s\)/{print $2; exit}')"
            [ -n "$cps" ] && [ -n "$sockets" ] && echo $((cps * sockets)) || echo "?"
            ;;
        CPU_THREADS) lscpu 2>/dev/null | awk -F': +' '/^CPU\(s\):/{print $2; exit}' || true ;;
        CPU_MAX_MHZ) lscpu 2>/dev/null | awk -F': +' '/CPU max MHz/{print $2; exit}' || true ;;
        MEM_TOTAL) free -h 2>/dev/null | awk '/^Mem:/{print $2}' || true ;;
        MEM_USED) free -h 2>/dev/null | awk '/^Mem:/{print $3}' || true ;;
        MEM_AVAILABLE) free -h 2>/dev/null | awk '/^Mem:/{print $NF}' || true ;;
        LOAD_AVG) cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || true ;;
        GPU_MODEL) lspci 2>/dev/null | grep -iE 'vga|3d controller' | sed -E 's/^[0-9a-f:.]+ [^:]+: //' | head -1 || true ;;

        BOOTLOADER)
            if [ -f /boot/grub/grub.cfg ]; then echo "grub"
            elif [ -d /boot/loader/entries ]; then echo "systemd-boot"
            else echo "?"
            fi
            ;;
        SECURE_BOOT) command -v bootctl >/dev/null 2>&1 && { bootctl status 2>/dev/null | awk -F': ' '/Secure Boot/{print $2; exit}' || true; } || echo "n/a (bootctl not installed)" ;;
        TPM2_SUPPORT) [ -e /dev/tpm0 ] && echo "yes" || echo "no" ;;
        VIRTUALIZATION) systemd-detect-virt 2>/dev/null || true ;;
        KERNEL_PARAMS_COUNT) wc -w < /proc/cmdline 2>/dev/null || true ;;
        KERNEL_CMDLINE) cat /proc/cmdline 2>/dev/null || true ;;
        BOOT_KERNELS_SIZE) du -sh /boot/kernels 2>/dev/null | cut -f1 || echo "n/a" ;;
        ESP_FREE) df -h /boot 2>/dev/null | awk 'NR==2{print $4}' || true ;;

        NET_INTERFACES) ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v '^lo$' | wc -l || true ;;
        NET_PRIMARY_IP) ip -4 -o addr show scope global 2>/dev/null | awk '{print $4; exit}' || true ;;
        NET_GATEWAY) ip route show default 2>/dev/null | awk '{print $3; exit}' || true ;;
        NET_DNS) awk '/^nameserver/{printf "%s, ", $2}' /etc/resolv.conf 2>/dev/null | sed 's/, $//' || true ;;
        NET_LISTENING_PORTS) ss -tlnH 2>/dev/null | wc -l || true ;;
        NET_MANAGER)
            systemctl is-active NetworkManager.service >/dev/null 2>&1 && echo "NetworkManager" \
                || { systemctl is-active systemd-networkd.service >/dev/null 2>&1 && echo "systemd-networkd" || echo "?"; }
            ;;
        FIREWALL_ENABLED) timeout 10 nix eval "$FLAKE_REF.networking.firewall.enable" 2>/dev/null || echo "?" ;;

        SSH_KEYS_COUNT) ls "$HOME"/.ssh/*.pub 2>/dev/null | wc -l || true ;;
        SUDO_KEYFILE_ACTIVE) timeout 10 nix eval "$FLAKE_REF.security.pam.services.sudo.rules.auth.keyfile.enable" 2>/dev/null || echo "?" ;;
        WHEEL_USERS) getent group wheel 2>/dev/null | awk -F: '{print $4}' | tr ',' '\n' | grep -c . || true ;;
        USER_ACCOUNTS) awk -F: '$3>=1000 && $3<30000' /etc/passwd 2>/dev/null | wc -l || true ;;
        LAST_LOGIN) last -1 -R 2>/dev/null | head -1 || true ;;

        JOURNAL_SIZE) journalctl --disk-usage 2>/dev/null | grep -oE 'take up [0-9.]+[A-Za-z]+' | awk '{print $3}' || true ;;
        JOURNAL_ERRORS_24H) journalctl -p err --since -24h --no-pager 2>/dev/null | wc -l || true ;;
        JOURNAL_WARNINGS_24H) journalctl -p warning..warning --since -24h --no-pager 2>/dev/null | wc -l || true ;;
        JOURNAL_BOOTS) journalctl --list-boots --no-pager 2>/dev/null | wc -l || true ;;
        PROCESS_COUNT) ps -e --no-headers 2>/dev/null | wc -l || true ;;
        ZOMBIE_COUNT) ps -eo stat --no-headers 2>/dev/null | grep -c '^Z' || true ;;

        DESKTOP) echo "${XDG_CURRENT_DESKTOP:-?}" ;;
        SESSION_TYPE) echo "${XDG_SESSION_TYPE:-?}" ;;
        LOCALE) echo "${LANG:-?}" ;;
        TIMEZONE) timedatectl show -p Timezone --value 2>/dev/null || true ;;
        SHELL_DEFAULT) echo "${SHELL:-?}" ;;

        *) echo "unknown field: $1" >&2; return 1 ;;
    esac
}

selected=("${field_names[@]}")
mode="labels"   # labels | noheadings | pairs

# Unique category names, in first-seen (display) order.
categories=()
for entry in "${field_order[@]}"; do
    cat="${entry##*:}"
    already=0
    for c in "${categories[@]}"; do [ "$c" = "$cat" ] && already=1 && break; done
    [ "$already" -eq 0 ] && categories+=("$cat")
done

# A few categories' natural uppercased name doesn't match the field-name
# prefix people actually type (PKGS_* fields, but category is "Packages") --
# these are the only aliases needed to make -o take either. Every other
# category (STORE, GENERATIONS, FLAKE, SYSTEM, DISK, BTRFS, GC, HARDWARE,
# BOOT, SESSION, HEALTH) already equals its own uppercased name.
declare -A category_aliases=(
    [PKGS]=Packages
    [NIXCONFIG]=NixConfig
    [NET]=Network
    [SEC]=Security
    [HW]=Hardware
)

# A single -o token: an exact field name, a category name/alias (expands to
# every field in that category, in field_order's order), or unresolved.
resolve_token() {
    local tok="${1^^}" c wanted_cat="" f found=0
    for f in "${field_names[@]}"; do
        if [ "$f" = "$tok" ]; then echo "$f"; return 0; fi
    done
    for c in "${categories[@]}"; do
        [ "${c^^}" = "$tok" ] && wanted_cat="$c" && break
    done
    [ -z "$wanted_cat" ] && wanted_cat="${category_aliases[$tok]:-}"
    if [ -n "$wanted_cat" ]; then
        for entry in "${field_order[@]}"; do
            if [ "${entry##*:}" = "$wanted_cat" ]; then
                echo "${entry%%:*}"
                found=1
            fi
        done
    fi
    [ "$found" -eq 1 ]
}

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output)
            arg="${2:-}"
            if [ "$arg" = "list" ] || [ "$arg" = "help" ]; then
                prev_cat=""
                for f in "${field_names[@]}"; do
                    cat="$(field_category "$f")"
                    [ "$cat" != "$prev_cat" ] && { echo; echo "-- $cat --"; prev_cat="$cat"; }
                    printf "%-24s %s\n" "$f" "$(field_desc "$f")"
                done
                exit 0
            fi
            IFS=',' read -r -a raw_tokens <<< "$arg"
            selected=()
            for tok in "${raw_tokens[@]}"; do
                resolved=()
                while IFS= read -r r; do resolved+=("$r"); done < <(resolve_token "$tok" || true)
                if [ "${#resolved[@]}" -eq 0 ]; then
                    echo "unknown field or category: $tok (try 'pacnix info -o list')" >&2
                    exit 1
                fi
                for r in "${resolved[@]}"; do
                    already=0
                    for s in "${selected[@]}"; do [ "$s" = "$r" ] && already=1 && break; done
                    [ "$already" -eq 0 ] && selected+=("$r")
                done
            done
            shift 2
            ;;
        -n|--noheadings) mode="noheadings"; shift ;;
        -p|--pairs) mode="pairs"; shift ;;
        -l|--list)
            prev_cat=""
            for f in "${field_names[@]}"; do
                cat="$(field_category "$f")"
                [ "$cat" != "$prev_cat" ] && { echo; echo "-- $cat --"; prev_cat="$cat"; }
                printf "%-24s %s\n" "$f" "$(field_desc "$f")"
            done
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done

prev_cat=""
for f in "${selected[@]}"; do
    value="$(field_value "$f")"
    case "$mode" in
        labels)
            cat="$(field_category "$f")"
            [ "$cat" != "$prev_cat" ] && { [ -n "$prev_cat" ] && echo; echo "-- $cat --"; prev_cat="$cat"; }
            printf "%-24s %s\n" "${f}:" "$value"
            ;;
        noheadings) printf "%s\n" "$value" ;;
        pairs) printf '%s="%s"\n' "$f" "$value" ;;
    esac
done
