#!/usr/bin/env bash
# Shared state, dirs, and helpers — sourced by all lib scripts.

BROKER_DIR="/tmp/sudo-broker-$(id -u)"
REQ_DIR="$BROKER_DIR/requests"
RESP_DIR="$BROKER_DIR/responses"
OUT_DIR="$BROKER_DIR/outputs"
SEEN_DIR="$BROKER_DIR/seen"
TIMEOUT="${SUDO_BROKER_TIMEOUT:-360}"
INSTALL_DIR="${SUDO_BROKER_INSTALL_DIR:-$HOME/.local/bin}"

# Real sudo's location varies by distro (e.g. /run/wrappers/bin/sudo on
# NixOS vs /usr/bin/sudo elsewhere) — search $PATH for it instead of
# hardcoding one. Has to explicitly skip any match that's actually THIS
# script (do_install symlinks it in as "sudo", earlier in $PATH, precisely
# so it intercepts the real one — a naive `command -v sudo` would just find
# itself again).
_find_real_sudo() {
    local self_real dir candidate candidate_real
    self_real="$(realpath "$0" 2>/dev/null || echo "$0")"
    local IFS=':'
    for dir in $PATH; do
        candidate="$dir/sudo"
        [[ -x "$candidate" ]] || continue
        candidate_real="$(realpath "$candidate" 2>/dev/null || echo "$candidate")"
        [[ "$candidate_real" == "$self_real" ]] && continue
        printf '%s' "$candidate"
        return 0
    done
    return 1
}
REAL_SUDO="$(_find_real_sudo)" || { echo "sudo broker: no real sudo binary found on \$PATH" >&2; exit 1; }

init_dirs() {
    mkdir -p "$REQ_DIR" "$RESP_DIR" "$OUT_DIR" "$SEEN_DIR"
    chmod 700 "$BROKER_DIR"
}

# 16 hex chars (8 random bytes), matching the old `openssl rand -hex 8`
# output shape (do_approve/do_deny match IDs against a 16-char pattern) —
# via /dev/urandom + od + tr instead, since openssl isn't guaranteed
# installed anywhere, while coreutils (od, tr, head) always is.
gen_id() { head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

b64enc() { printf '%s' "$*" | base64 -w0; }
b64dec() { printf '%s' "$*" | base64 -d; }

read_field() { grep "^${2}=" "$1" | cut -d= -f2-; }
req_cmd()    { b64dec "$(read_field "$1" CMD)"; }
req_age()    { echo $(( $(date +%s) - $(read_field "$1" TIME) )); }
req_ttl()    { echo $(( TIMEOUT - $(req_age "$1") )); }

cleanup_expired() {
    local f id pipe
    for f in "$REQ_DIR"/*.req; do
        [[ -f "$f" ]] || continue
        id=$(basename "$f" .req)
        [[ $(req_ttl "$f") -le 0 ]] || continue
        pipe="$RESP_DIR/$id.pipe"
        [[ -p "$pipe" ]] && timeout 2 bash -c "printf 'DENIED:1\n' > '$pipe'" 2>/dev/null || true
        rm -f "$f" "$SEEN_DIR/$id"
    done
}

# Box drawing ─────────────────────────────────────────────────────────────────
W=62
box_top()   { printf '╔%s╗\n' "$(printf '═%.0s' $(seq 1 $((W-2))))"; }
box_bot()   { printf '╚%s╝\n' "$(printf '═%.0s' $(seq 1 $((W-2))))"; }
box_sep()   { printf '╠%s╣\n' "$(printf '═%.0s' $(seq 1 $((W-2))))"; }
box_line()  { printf '║ %-*s ║\n' "$((W-4))" "$*"; }
box_blank() { box_line ""; }
