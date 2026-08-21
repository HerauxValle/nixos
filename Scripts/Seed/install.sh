#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN="$SCRIPT_DIR/main.py"
SYMLINK="/usr/local/bin/sd"
SUDOERS_FILE="/etc/sudoers.d/sd"
PRIV_DIR="/usr/local/lib/sd/priv"

ACTION="install"
ENABLE_ROOT=0
DISABLE_ROOT=0

# Parse args
for arg in "$@"; do
    case "$arg" in
        --install) ACTION="install" ;;
        --uninstall|--remove) ACTION="uninstall" ;;
        --enable-root) ENABLE_ROOT=1 ;;
        --disable-root) DISABLE_ROOT=1 ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

require_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    elif command -v brew >/dev/null 2>&1; then
        echo "brew"
    else
        echo "unknown"
    fi
}

install_package() {
    local pkg=$1
    local pm=$2

    case "$pm" in
        apt) require_root apt-get update && require_root apt-get install -y "$pkg" ;;
        yum) require_root yum install -y "$pkg" ;;
        dnf) require_root dnf install -y "$pkg" ;;
        pacman) require_root pacman -S --noconfirm "$pkg" ;;
        apk) require_root apk add "$pkg" ;;
        brew) brew install "$pkg" ;;
        *) return 1 ;;
    esac
}

get_package_name() {
    local cmd=$1
    local pm=$2

    # Map command names to package names (package manager agnostic)
    case "$cmd" in
        btrfs) echo "btrfs-progs" ;;
        cryptsetup) echo "cryptsetup" ;;
        mkfs.ext4|mkfs) echo "e2fsprogs" ;;
        ip) echo "iproute2" ;;
        iptables) echo "iptables" ;;
        losetup) echo "util-linux" ;;
        gcc) echo "build-essential" ;;
        *) echo "$cmd" ;;
    esac
}

check_architecture() {
    local arch=$(uname -m)
    echo "→ System architecture: $arch"

    case "$arch" in
        x86_64)
            echo "✓ x86_64: Full syscall support"
            ;;
        aarch64|arm64)
            echo "✓ ARM64: Full syscall support"
            ;;
        armv7l|armv6l)
            echo "⚠ ARMv7/v6: Partial syscall support (some may differ)"
            ;;
        i386|i686)
            echo "⚠ i386: 32-bit architecture (some syscalls may differ)"
            ;;
        *)
            echo "⚠ Unknown architecture: $arch (syscall mapping may be inaccurate)"
            ;;
    esac
    echo ""
}

check_apparmor() {
    echo "→ Checking AppArmor availability..."

    if [ -f /sys/kernel/security/apparmor/abi ]; then
        if command -v apparmor_parser >/dev/null 2>&1; then
            echo "✓ AppArmor available (kernel + parser)"
            return 0
        else
            echo "⚠ AppArmor kernel available but apparmor_parser missing"
            echo "  (will continue without AppArmor profile enforcement)"
            return 0
        fi
    else
        echo "⚠ AppArmor not available (no kernel support)"
        echo "  (will continue without AppArmor profile enforcement)"
        return 0
    fi
}

check_and_install_deps() {
    check_architecture
    check_apparmor
    echo "→ Checking system compatibility..."
    echo ""

    local pm=$(detect_package_manager)
    local missing=()
    local cannot_install=()

    # Check for required commands
    local required_cmds=(
        "sudo:critical"
        "mount:critical"
        "umount:critical"
        "mkdir:critical"
        "nsenter:critical"
        "gcc:feature"
        "pgrep:critical"
        "tee:critical"
        "cp:critical"
        "ln:critical"
        "rm:critical"
        "mknod:critical"
        "chown:critical"
        "btrfs:feature"
        "cryptsetup:feature"
        "mkfs:feature"
        "ip:feature"
        "iptables:feature"
        "losetup:feature"
        "fuser:critical"
    )

    local critical_missing=0
    local feature_missing=0

    for entry in "${required_cmds[@]}"; do
        IFS=':' read -r cmd category <<< "$entry"

        if ! command -v "$cmd" >/dev/null 2>&1; then
            if [[ "$category" == "critical" ]]; then
                cannot_install+=("$cmd")
                ((critical_missing++))
            else
                missing+=("$cmd")
                ((feature_missing++))
            fi
        fi
    done

    # Report missing critical dependencies
    if [[ $critical_missing -gt 0 ]]; then
        echo "✗ INCOMPATIBLE: Missing critical command(s):"
        for cmd in "${cannot_install[@]}"; do
            echo "  - $cmd"
        done
        echo ""
        echo "This system cannot run Seed. These are kernel/core utilities that must be present."
        return 1
    fi

    # Try to install missing feature dependencies
    if [[ $feature_missing -gt 0 ]]; then
        echo "⚠ Missing feature dependencies:"
        for cmd in "${missing[@]}"; do
            echo "  - $cmd"
        done
        echo ""

        if [[ "$pm" == "unknown" ]]; then
            echo "Cannot auto-detect package manager. Install manually or use known package manager."
            return 1
        fi

        echo "→ Attempting to install missing packages (PM: $pm)..."

        for cmd in "${missing[@]}"; do
            local pkg=$(get_package_name "$cmd" "$pm")
            if install_package "$pkg" "$pm" 2>/dev/null; then
                echo "  ✓ Installed $pkg"
            else
                echo "  ✗ Failed to install $pkg (may be optional)"
            fi
        done
    fi

    echo "✓ System compatibility check passed"
    return 0
}

install() {
    # Check system compatibility first
    if ! check_and_install_deps; then
        echo ""
        echo "Installation cannot proceed."
        exit 1
    fi

    echo ""
    chmod +x "$MAIN"
    require_root ln -sf "$MAIN" "$SYMLINK"
    echo "✓ sd installed → $SYMLINK"
    echo ""
    echo "Next steps:"
    echo "  • Basic mode (prompt for sudo password):"
    echo "    → run: sd <command>"
    echo ""
    echo "  • Passwordless mode (optional, requires --enable-root):"
    echo "    → run: ./install.sh --enable-root"
}

uninstall() {
    echo "→ Uninstalling Seed"

    # Remove symlink
    if [ -L "$SYMLINK" ]; then
        require_root rm "$SYMLINK"
        echo "✓ removed sd symlink"
    fi

    # Remove privilege helper directory (sd-priv, sd-priv-iso, sd-seccomp)
    if [ -d "$PRIV_DIR" ]; then
        require_root rm -rf "$PRIV_DIR"
        echo "✓ removed privilege helper directory"
    fi

    # Remove sudoers config
    if [ -f "$SUDOERS_FILE" ]; then
        require_root rm -f "$SUDOERS_FILE"
        echo "✓ removed sudoers config"
    fi

    echo "✓ Seed uninstalled"
}

apply_security_patches() {
    local helper="$PRIV_DIR/sd-priv-iso"
    echo "→ Applying security patches to helper..."

    # Patch: Add rprivate flag to mount options (prevent propagation)
    if ! grep -q "ro,bind,nosuid,nodev,noexec,rprivate" "$helper"; then
        require_root sed -i 's/ro,bind,nosuid,nodev,noexec$/ro,bind,nosuid,nodev,noexec,rprivate/' "$helper"
        if grep -q "ro,bind,nosuid,nodev,noexec,rprivate" "$helper"; then
            echo "✓ Mount propagation flag (rprivate) applied"
        else
            echo "⚠ Mount propagation patch may have failed, continuing..."
        fi
    else
        echo "✓ Mount propagation flag already patched"
    fi
}

build_sd_init() {
    echo "→ Building sd-init C binary..."
    if ! command -v gcc >/dev/null 2>&1; then
        echo "✗ gcc not found. Install build-essential or gcc."
        return 1
    fi

    # Build to temp location, never in project directory
    TEMP_BUILD=$(mktemp -d)

    # Copy sources to temp
    cp "$SCRIPT_DIR/helpers/sd-init.c" "$TEMP_BUILD/"
    cp "$SCRIPT_DIR/helpers/sd-init-seccomp.h" "$TEMP_BUILD/"
    cp "$SCRIPT_DIR/helpers/sd-init-caps.h" "$TEMP_BUILD/"

    # Compile in temp
    (cd "$TEMP_BUILD" && gcc -Wall -Wextra -Werror -O2 -static -o sd-init sd-init.c -static) || {
        echo "✗ sd-init build failed"
        rm -rf "$TEMP_BUILD"
        return 1
    }

    BUILT_BINARY="$TEMP_BUILD/sd-init"
    echo "✓ sd-init built successfully (temp location)"
}

verify_sd_init() {
    local installed_binary="$PRIV_DIR/sd-init"
    local expected_version="1.3.14"

    # If already installed, check version and hash
    if [ -f "$installed_binary" ]; then
        local installed_ver=$("$installed_binary" --version 2>/dev/null || echo "unknown")

        # Check version first
        if [ "$installed_ver" != "$expected_version" ]; then
            echo "→ sd-init version mismatch (installed: $installed_ver, expected: $expected_version)"
            build_sd_init || return 1
            return 0
        fi

        # Check hash if available
        if command -v sha256sum >/dev/null 2>&1; then
            local hash_file="$PRIV_DIR/sd-init.sha256"
            if [ -f "$hash_file" ]; then
                local expected_hash=$(cat "$hash_file")
                local current_hash=$(sha256sum "$installed_binary" 2>/dev/null | awk '{print $1}')

                if [ "$expected_hash" != "$current_hash" ]; then
                    echo "→ sd-init hash mismatch (file corruption or tampering detected)"
                    build_sd_init || return 1
                    return 0
                fi
            fi
        fi

        echo "✓ sd-init verified (v$installed_ver)"
        return 0
    fi

    # Not installed yet, build it
    echo "→ sd-init not installed, building..."
    build_sd_init || return 1
    return 0
}

enable_root() {
    echo "→ Installing privilege helpers and sd-init"

    # Verify and build sd-init if needed
    verify_sd_init || return 1

    require_root mkdir -p "$PRIV_DIR"
    require_root cp "$SCRIPT_DIR/helpers/sd-priv" "$PRIV_DIR/"
    require_root cp "$SCRIPT_DIR/helpers/isolated" "$PRIV_DIR/sd-priv-iso"

    # Copy built sd-init binary to priv directory
    if [ -n "$BUILT_BINARY" ] && [ -f "$BUILT_BINARY" ]; then
        require_root cp "$BUILT_BINARY" "$PRIV_DIR/sd-init"

        # Generate and cache SHA256 hash after install
        if command -v sha256sum >/dev/null 2>&1; then
            require_root bash -c "sha256sum '$PRIV_DIR/sd-init' | awk '{print \$1}' > '$PRIV_DIR/sd-init.sha256'"
            require_root chmod 600 "$PRIV_DIR/sd-init.sha256"
            echo "✓ Hash cached: $PRIV_DIR/sd-init.sha256"
        fi

        # Clean up temp build directory
        if [ -n "$TEMP_BUILD" ] && [ -d "$TEMP_BUILD" ]; then
            rm -rf "$TEMP_BUILD"
        fi
    else
        echo "✗ sd-init binary not found. Build may have failed."
        [ -n "$TEMP_BUILD" ] && [ -d "$TEMP_BUILD" ] && rm -rf "$TEMP_BUILD"
        return 1
    fi

    require_root chown -R root:root /usr/local/lib/sd
    require_root chmod 755 /usr/local/lib/sd/priv/sd-init
    require_root chmod -R 755 /usr/local/lib/sd

    # Apply security patches to helpers
    apply_security_patches

    require_root bash -c "cat > $SUDOERS_FILE" <<'EOF'
# Seed container runtime — privilege helpers (safe and isolated)
Cmnd_Alias SD_PRIV = /usr/local/lib/sd/priv/sd-priv
Cmnd_Alias SD_PRIV_ISO = /usr/local/lib/sd/priv/sd-priv-iso
Cmnd_Alias SD_INIT = /usr/local/lib/sd/priv/sd-init
%wheel ALL=(root) NOPASSWD: SD_PRIV, SD_PRIV_ISO, SD_INIT
EOF

    require_root chmod 440 "$SUDOERS_FILE"
    require_root visudo -c -f "$SUDOERS_FILE"

    echo "✓ passwordless privilege escalation enabled (sd-priv, sd-priv-iso, sd-init)"
}

disable_root() {
    echo "→ Disabling passwordless privilege escalation"
    require_root rm -f "$SUDOERS_FILE"
    echo "✓ passwordless mode disabled (will prompt for passwords)"
}

case "$ACTION" in
    install) install ;;
    uninstall) uninstall ;;
esac

if [[ $ENABLE_ROOT -eq 1 ]]; then
    enable_root
fi

if [[ $DISABLE_ROOT -eq 1 ]]; then
    disable_root
fi
