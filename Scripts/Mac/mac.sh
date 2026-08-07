#!/usr/bin/env bash
# &desc: "Temporary MAC spoofing -- mac <addr>/preset/default. Kernel-level (ip link), never touches NetworkManager's saved connection, reverts on reboot/replug."

declare -A PRESETS=(
    [alexa]="A8:E6:21:92:2C:E1"
)

MAC_RE='^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'
PRESET_NAMES="${!PRESETS[*]}"

usage() {
    echo "Usage:"
    echo "  mac <mac-addr>     Spoof to a specific address (temporary)"
    echo "  mac preset <name>  Spoof to a named preset ($PRESET_NAMES)"
    echo "  mac default        Restore original hardware address"
    exit 1
}

iface() {
    ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1
}

set_mac() {
    local iface="$1" addr="$2"
    sudo ip link set "$iface" down
    sudo ip link set "$iface" address "$addr"
    sudo ip link set "$iface" up
    ip link show "$iface" | awk '/link\/ether/ {print "MAC: " $2}'
}

[[ -z "$1" ]] && usage

IFACE=$(iface)
[[ -z "$IFACE" ]] && { echo "Could not determine active interface"; exit 1; }

case "$1" in
    default)
        PERM_MAC=$(ip link show "$IFACE" | awk '/permaddr/ {print $NF}')
        if [[ -z "$PERM_MAC" ]]; then
            echo "$IFACE: already on original address"
            exit 0
        fi
        echo "$IFACE: restoring original ($PERM_MAC)"
        set_mac "$IFACE" "$PERM_MAC"
        ;;
    preset)
        [[ -z "$2" ]] && usage
        ADDR="${PRESETS[$2]}"
        [[ -z "$ADDR" ]] && { echo "No preset named '$2' (have: $PRESET_NAMES)"; exit 1; }
        echo "$IFACE: spoofing to preset '$2' ($ADDR)"
        set_mac "$IFACE" "$ADDR"
        ;;
    *)
        [[ "$1" =~ $MAC_RE ]] || usage
        echo "$IFACE: spoofing to $1"
        set_mac "$IFACE" "$1"
        ;;
esac
