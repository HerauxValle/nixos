#!/usr/bin/env bash
# lib/request.sh -- submit a broker request and block until approved/denied/timed out.
# Called by sudo when no TTY is detected. Not meant to be run directly.

# Write to the real terminal regardless of stdout/stderr redirection.
# Falls back to stderr if /dev/tty is unavailable.
tty_print() {
    { printf '%s\n' "$@" > /dev/tty; } 2>/dev/null || printf '%s\n' "$@" >&2 || true
}

notify() {
    local title="$1" body="$2"
    # Try desktop notification, silently skip if unavailable
    command -v notify-send &>/dev/null && \
        notify-send --urgency=critical --expire-time=0 "$title" "$body" 2>/dev/null || true
}

do_request() {
    local CMD="$*"
    local ID PIPE OUT ERR NOW HUMAN_TIME

    init_dirs
    cleanup_expired

    ID=$(gen_id)
    PIPE="$RESP_DIR/$ID.pipe"
    OUT="$OUT_DIR/$ID.out"
    ERR="$OUT_DIR/$ID.err"
    NOW=$(date +%s)
    HUMAN_TIME=$(date -d "@$NOW" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$NOW" '+%Y-%m-%d %H:%M:%S')

    # ── auto mode: skip approval unless blacklisted ───────────────────────────
    if auto_is_active; then
        local _bl_match
        if _bl_match=$(blacklist_check "$CMD"); then
            {
                box_top
                box_line "SUDO BROKER -- BLACKLISTED (auto mode bypassed)"
                box_sep
                box_line "Command : sudo $CMD"
                box_line "Pattern : $_bl_match"
                box_line "Falling through to normal approval flow."
                box_bot
            } >&2
        else
            local _AUTO_EXIT=0
            "$REAL_SUDO" -n bash -c "$CMD" || _AUTO_EXIT=$?
            exit "$_AUTO_EXIT"
        fi
    fi

    mkfifo "$PIPE"
    chmod 600 "$PIPE"

    {
        echo "CMD=$(b64enc "$CMD")"
        echo "TIME=$NOW"
        echo "USER=$(whoami)"
        echo "PID=$$"
    } > "$REQ_DIR/$ID.req"

    # ── visible to the AI (stderr) ────────────────────────────────────────────
    {
        box_top
        box_line "SUDO BROKER -- REQUEST SUBMITTED"
        box_sep
        box_line "Request ID  : $ID"
        box_line "Command     : sudo $CMD"
        box_line "Submitted   : $HUMAN_TIME"
        box_line "Expires in  : ${TIMEOUT}s"
        box_sep
        box_blank
        box_line "Tell the user to run one of the following:"
        box_blank
        box_line "  sudo --adv:approve            approve the latest request"
        box_line "  sudo --adv:approve $ID"
        box_line "  sudo --adv:live               interactive watcher"
        box_blank
        box_line "  sudo --adv:deny               deny the latest request"
        box_line "  sudo --adv:deny $ID"
        box_blank
        box_line "  sudo --adv:pending            list all pending requests"
        box_blank
        box_bot
    } >&2

    # ── visible to the user on their real terminal ────────────────────────────
    {
        tty_print ""
        tty_print "┌──────────────────────────────────────────────────────────────┐"
        tty_print "│  SUDO REQUEST -- action needed                                │"
        tty_print "├──────────────────────────────────────────────────────────────┤"
        tty_print "│  ID      : $ID"
        tty_print "│  Command : sudo $CMD"
        tty_print "│  Expires : ${TIMEOUT}s from now"
        tty_print "├──────────────────────────────────────────────────────────────┤"
        tty_print "│  sudo --adv:approve     ← approve latest"
        tty_print "│  sudo --adv:approve $ID"
        tty_print "│  sudo --adv:deny        ← deny latest"
        tty_print "│  sudo --adv:live        ← interactive watcher"
        tty_print "└──────────────────────────────────────────────────────────────┘"
        tty_print ""
    }

    # ── kitty OSC 9 notification (visible even in alt-screen / fullscreen TUI) ──
    # /dev/tty is unavailable to Claude Code subprocesses, so walk the process
    # tree to find the PTY of the ancestor terminal and write directly to it.
    if [[ -n "${KITTY_WINDOW_ID:-}" ]]; then
        _find_ancestor_pts() {
            local pid=$$
            while [[ $pid -gt 1 ]]; do
                pid=$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null) || break
                [[ -z $pid || $pid -eq 0 ]] && break
                for fd in /proc/$pid/fd/*; do
                    local target
                    target=$(readlink "$fd" 2>/dev/null) || continue
                    [[ $target == /dev/pts/* ]] && echo "$target" && return 0
                done
            done
            return 1
        }
        _pts=$(_find_ancestor_pts 2>/dev/null) && \
            printf '\033]9;sudo approve -- run: sudo --adv:approve %s\a' "$ID" > "$_pts" 2>/dev/null || true
    fi

    # ── desktop notification as a backup nudge ────────────────────────────────
    notify "sudo request pending [$ID]" \
        "sudo $CMD\n\nRun: sudo --adv:approve"

    # ── block until response ──────────────────────────────────────────────────
    local RESPONSE
    if ! RESPONSE=$(timeout "$TIMEOUT" cat "$PIPE" 2>/dev/null); then
        {
            box_top
            box_line "SUDO BROKER -- TIMED OUT [$ID]"
            box_sep
            box_line "No approval received within ${TIMEOUT}s. Request discarded."
            box_bot
        } >&2
        tty_print "sudo-broker: request [$ID] timed out."
        rm -f "$REQ_DIR/$ID.req" "$PIPE"
        exit 1
    fi

    rm -f "$PIPE" "$REQ_DIR/$ID.req"

    local STATUS EXIT_CODE ENCODED_MSG USER_MSG=""
    STATUS="${RESPONSE%%:*}"
    local _rest="${RESPONSE#*:}"
    EXIT_CODE="${_rest%%:*}"
    ENCODED_MSG="${_rest#*:}"
    [[ "$ENCODED_MSG" != "$EXIT_CODE" ]] && USER_MSG=$(b64dec "$ENCODED_MSG" 2>/dev/null || echo "")

    if [[ "$STATUS" == "DENIED" ]]; then
        {
            box_top
            box_line "SUDO BROKER -- DENIED [$ID]"
            box_sep
            box_line "The user denied: sudo $CMD"
            [[ -n "$USER_MSG" ]] && box_line "Message   : $USER_MSG"
            box_bot
        } >&2
        tty_print "sudo-broker: request [$ID] denied.${USER_MSG:+ Message: $USER_MSG}"
        exit 1
    fi

    {
        box_top
        box_line "SUDO BROKER -- APPROVED [$ID]"
        box_sep
        box_line "Command   : sudo $CMD"
        box_line "Exit code : $EXIT_CODE"
        [[ -n "$USER_MSG" ]] && box_line "Message   : $USER_MSG"
        box_line "Output follows below."
        box_bot
    } >&2

    tty_print "sudo-broker: request [$ID] approved (exit $EXIT_CODE).${USER_MSG:+ Message: $USER_MSG}"

    [[ -f "$OUT" ]] && { cat "$OUT"; rm -f "$OUT"; }
    [[ -f "$ERR" ]] && { cat "$ERR" >&2; rm -f "$ERR"; }

    exit "${EXIT_CODE:-0}"
}
