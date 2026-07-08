#!/usr/bin/env bash
# lib/auto.sh -- auto mode with multi-session, per-terminal scoping.
#
# Two session types:
#   global  -- writes NOPASSWD sudoers rule, works across all terminals + no-TTY
#   session -- timestamp keepalive (sudo -v every 4min) for the specific PTY only,
#             no sudoers change; other terminals still require password
#
# Session files: $SESSIONS_DIR/<id>.session
#   TYPE=global|session
#   PTY=/dev/pts/N          (session only)
#   EXPIRES=never|<unix_ts>
#   ENABLED_AT=<unix_ts>
# Watcher PID: $SESSIONS_DIR/<id>.pid

SESSIONS_DIR="$BROKER_DIR/sessions"
AUTO_SUDOERS="/etc/sudoers.d/sudo-broker-auto"
AUTO_USER="$(id -un)"

# ── helpers ───────────────────────────────────────────────────────────────────

_sessions_init() {
    init_dirs
    mkdir -p "$SESSIONS_DIR"
    chmod 700 "$SESSIONS_DIR"
}

_session_read()    { grep "^${2}=" "$1" 2>/dev/null | cut -d= -f2-; }

_session_expired() {
    local exp
    exp=$(_session_read "$1" EXPIRES)
    [[ "$exp" == "never" ]] && return 1
    (( $(date +%s) >= exp ))
}

_global_sessions_exist() {
    local f
    for f in "$SESSIONS_DIR"/*.session; do
        [[ -f "$f" ]] || continue
        _session_expired "$f" && continue
        [[ $(_session_read "$f" TYPE) == "global" ]] && return 0
    done
    return 1
}

_session_kill_watcher() {
    local pid_file="$SESSIONS_DIR/${1}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid; pid=$(cat "$pid_file" 2>/dev/null)
        [[ -n $pid ]] && kill "$pid" 2>/dev/null || true
        rm -f "$pid_file"
    fi
}

_session_remove() {
    local id="$1"
    _session_kill_watcher "$id"
    rm -f "$SESSIONS_DIR/$id.session"
    # Remove sudoers only when no global sessions remain
    _global_sessions_exist || "$REAL_SUDO" -n rm -f "$AUTO_SUDOERS" 2>/dev/null || true
}

_auto_write_sudoers() {
    # /etc/sudoers.d/ isn't guaranteed to already exist (e.g. a fresh NixOS
    # install with nothing ever dropped there yet) -- `tee` won't create a
    # missing parent, so ensure it's there first. Relies on the distro's
    # sudoers already `@includedir`-ing /etc/sudoers.d (true by default on
    # effectively every mainstream distro, NixOS included); if it somehow
    # isn't, this file is silently unread rather than breaking anything.
    "$REAL_SUDO" mkdir -p "$(dirname "$AUTO_SUDOERS")"
    printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$AUTO_USER" \
        | "$REAL_SUDO" tee "$AUTO_SUDOERS" > /dev/null
    "$REAL_SUDO" chmod 440 "$AUTO_SUDOERS"
}

# ── active checks (used by main script + request.sh) ─────────────────────────

# True if the given TTY (or empty for non-TTY) has auto mode active.
# - global sessions apply everywhere
# - session-type sessions apply only to their specific PTY
auto_is_active_for_tty() {
    [[ -d "$SESSIONS_DIR" ]] || return 1
    local want_tty="${1:-}" f now
    now=$(date +%s)
    for f in "$SESSIONS_DIR"/*.session; do
        [[ -f "$f" ]] || continue
        local exp; exp=$(_session_read "$f" EXPIRES)
        if [[ "$exp" != "never" ]] && (( now >= exp )); then
            _session_remove "$(basename "$f" .session)" &>/dev/null
            continue
        fi
        local type; type=$(_session_read "$f" TYPE)
        if [[ $type == "global" ]]; then
            return 0
        elif [[ $type == "session" && -n "$want_tty" ]]; then
            local pts; pts=$(_session_read "$f" PTY)
            [[ "$pts" == "$want_tty" ]] && return 0
        fi
    done
    return 1
}

# Convenience: no-TTY path (broker) -- only global sessions
auto_is_active() { auto_is_active_for_tty ""; }

# ── captcha ───────────────────────────────────────────────────────────────────

_captcha_print() {
    local s="$1" wj=$'\xe2\x81\xa0' i
    for (( i=0; i<${#s}; i++ )); do
        printf '%s' "${s:$i:1}"
        (( i+1 < ${#s} )) && printf '%s' "$wj"
    done
    printf '\n'
}

# ── arg parsing ───────────────────────────────────────────────────────────────

_parse_enable_arg() {
    local arg="${1#-}"
    _AUTO_NO_WARN=0; _AUTO_EXPIRES="never"

    if [[ $arg == *-no-warning ]]; then
        _AUTO_NO_WARN=1; arg="${arg%-no-warning}"
    elif [[ $arg == "no-warning" ]]; then
        _AUTO_NO_WARN=1; arg=""
    fi
    [[ -z $arg ]] && return 0

    if [[ $arg =~ ^([0-9]+)-([smhd])$ ]]; then
        local val="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[2]}" secs
        case $unit in
            s) secs=$val ;; m) secs=$(( val*60 )) ;;
            h) secs=$(( val*3600 )) ;; d) secs=$(( val*86400 )) ;;
        esac
        _AUTO_EXPIRES=$(( $(date +%s) + secs ))
        return 0
    fi

    echo "Unknown argument: '$arg'" >&2
    echo "Usage: sudo --adv:auto-enable|auto-session[[-<N>-<s|m|h|d>][-no-warning]]" >&2
    return 1
}

# ── core: start a session ────────────────────────────────────────────────────

# _auto_new_session TYPE [PTY]
# Expects _AUTO_NO_WARN and _AUTO_EXPIRES set by caller.
_auto_new_session() {
    local type="$1" pts="${2:-}"

    local expires_str
    [[ $_AUTO_EXPIRES == "never" ]] \
        && expires_str="PERMANENT" \
        || expires_str="until $(date -d "@$_AUTO_EXPIRES" '+%Y-%m-%d %H:%M:%S')"

    # ── warning + captcha ─────────────────────────────────────────────────────
    if [[ $_AUTO_NO_WARN -eq 0 ]]; then
        local RED=$'\033[0;31m' BOLD=$'\033[1m' RESET=$'\033[0m'
        printf '\n%s%s⚠  WARNING: DANGEROUS MODE%s\n' "$RED" "$BOLD" "$RESET"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Auto mode lets ALL sudo commands run WITHOUT per-command approval."
        echo "Any process (including AI agents) can escalate to root freely."
        printf 'Duration: %s\n' "$expires_str"
        [[ $type == "session" ]] && printf 'Scope:    this terminal only (%s)\n' "$pts"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        local captcha
        captcha=$(head -c 256 /dev/urandom | tr -dc 'A-Za-z0-9' | tr -d 'lIO0' | cut -c1-8)
        echo "Type this string to confirm (do not copy-paste it):"
        echo ""; printf '  '; _captcha_print "$captcha"; echo ""

        local input
        read -r -p "  Confirm: " input
        if [[ "$input" != "$captcha" ]]; then
            echo ""; echo "Incorrect or copy-pasted. Auto mode NOT enabled."
            return 1
        fi
        echo ""
    fi

    # ── authenticate ──────────────────────────────────────────────────────────
    echo "Authenticating..."
    "$REAL_SUDO" -v || { echo "Authentication failed. Auto mode NOT enabled."; return 1; }

    # ── write sudoers only for global sessions ────────────────────────────────
    if [[ $type == "global" ]]; then
        _global_sessions_exist || _auto_write_sudoers
    fi

    # ── create session file ───────────────────────────────────────────────────
    local id; id=$(gen_id)
    local sf="$SESSIONS_DIR/$id.session"
    local pid_file="$SESSIONS_DIR/$id.pid"
    {
        echo "TYPE=$type"
        echo "EXPIRES=$_AUTO_EXPIRES"
        echo "ENABLED_AT=$(date +%s)"
        [[ -n $pts ]] && echo "PTY=$pts"
    } > "$sf"; chmod 600 "$sf"

    # ── start watcher ─────────────────────────────────────────────────────────
    local sessions_dir="$SESSIONS_DIR" sudoers="$AUTO_SUDOERS" real_sudo="$REAL_SUDO"
    local auto_expires="$_AUTO_EXPIRES" session_type="$type"
    (
        _cleanup() {
            rm -f "$sf" "$pid_file"
            # Remove sudoers only if no global sessions remain
            local f any=0
            for f in "$sessions_dir"/*.session; do
                [[ -f "$f" ]] && [[ $( grep "^TYPE=" "$f" 2>/dev/null | cut -d= -f2-) == "global" ]] \
                    && any=1 && break
            done
            (( any )) || "$real_sudo" -n rm -f "$sudoers" 2>/dev/null || true
        }
        trap '_cleanup' EXIT

        if [[ $session_type == "session" ]]; then
            # Watch PTY + keepalive sudo -v every 4 min so timestamp stays valid
            local ticks=0
            while [[ -e "$pts" ]]; do
                sleep 1
                # Expiry check
                if [[ "$auto_expires" != "never" ]] && (( $(date +%s) >= auto_expires )); then
                    break
                fi
                # Refresh timestamp every 240 seconds
                (( ++ticks < 240 )) && continue
                ticks=0
                "$real_sudo" -nv 2>/dev/null || break
            done
        elif [[ $session_type == "global" ]]; then
            if [[ "$auto_expires" == "never" ]]; then
                sleep infinity
            else
                sleep $(( auto_expires - $(date +%s) ))
            fi
        fi
    ) &
    local w_pid=$!
    echo "$w_pid" > "$pid_file"
    disown "$w_pid"

    # ── confirm ───────────────────────────────────────────────────────────────
    echo ""
    if [[ $type == "session" ]]; then
        printf '✓ Auto mode enabled for this terminal (%s)' "$pts"
    else
        printf '✓ Auto mode enabled (global)'
    fi
    [[ $_AUTO_EXPIRES == "never" ]] && echo "." || echo " $expires_str."
    echo "  Disable with: sudo --adv:auto-disable"
    echo ""
}

# ── public commands ───────────────────────────────────────────────────────────

do_auto_enable() {
    _sessions_init
    local _AUTO_NO_WARN _AUTO_EXPIRES
    _parse_enable_arg "${1:-}" || return 1
    _auto_new_session global
}

do_auto_session() {
    _sessions_init
    local pts; pts=$(tty 2>/dev/null) || true
    if [[ -z "$pts" || "$pts" == "not a tty" ]]; then
        echo "Error: --adv:auto-session must be run from an interactive terminal." >&2
        return 1
    fi
    local _AUTO_NO_WARN _AUTO_EXPIRES
    _parse_enable_arg "${1:-}" || return 1
    _auto_new_session session "$pts"
}

do_auto_disable() {
    _sessions_init
    local f id count=0
    for f in "$SESSIONS_DIR"/*.session; do
        [[ -f "$f" ]] || continue
        id=$(basename "$f" .session)
        _session_kill_watcher "$id"
        rm -f "$f"
        (( count++ )) || true
    done
    "$REAL_SUDO" -n rm -f "$AUTO_SUDOERS" 2>/dev/null || true
    (( count > 0 )) && echo "Auto mode disabled ($count session(s) removed)." \
                    || echo "Auto mode was not active."
}

do_auto_toggle() {
    _sessions_init
    if auto_is_active_for_tty "$(tty 2>/dev/null || echo '')"; then
        do_auto_disable
    else
        local _AUTO_NO_WARN=0 _AUTO_EXPIRES="never"
        _auto_new_session global
    fi
}

do_auto_status() {
    _sessions_init
    local f count=0 now; now=$(date +%s)
    for f in "$SESSIONS_DIR"/*.session; do
        [[ -f "$f" ]] || continue
        _session_expired "$f" && continue
        (( count++ )) || true
        local type exp pts enabled_at
        type=$(_session_read "$f" TYPE)
        exp=$(_session_read "$f" EXPIRES)
        pts=$(_session_read "$f" PTY)
        enabled_at=$(_session_read "$f" ENABLED_AT)
        printf '  [%d] %-7s  started=%s' "$count" "$type" \
            "$(date -d "@$enabled_at" '+%H:%M:%S')"
        if [[ "$exp" == "never" ]]; then
            printf '  expires=never'
        else
            local rem=$(( exp - now ))
            printf '  expires=%s (in %dh %dm %ds)' \
                "$(date -d "@$exp" '+%H:%M:%S')" \
                "$(( rem/3600 ))" "$(( (rem%3600)/60 ))" "$(( rem%60 ))"
        fi
        [[ -n $pts ]] && printf '  tty=%s' "$pts"
        echo ""
    done
    if (( count == 0 )); then echo "Auto mode: OFF"
    else echo ""; echo "Auto mode: ON ($count active session(s))"
    fi
}

# Run a blacklisted command with mandatory password even in auto mode.
auto_run_blacklisted() {
    echo "[sudo broker] Blacklisted command -- password required." >&2
    if _global_sessions_exist; then
        # Global mode: temporarily remove NOPASSWD rule, run, restore
        "$REAL_SUDO" -n rm -f "$AUTO_SUDOERS" 2>/dev/null || true
        local _exit=0; "$REAL_SUDO" "$@" || _exit=$?
        _auto_write_sudoers 2>/dev/null || true
        return "$_exit"
    else
        # Session mode: invalidate timestamp so sudo prompts for password
        "$REAL_SUDO" -k 2>/dev/null || true
        "$REAL_SUDO" "$@"
    fi
}
