#!/usr/bin/env bash
# lib/deny.sh — deny a pending request (latest or by ID).
# Usage: do_deny [ID] [message...]

do_deny() {
    local ID="${1:-}" MSG=""
    [[ $# -gt 0 ]] && shift
    # If first arg doesn't look like a request ID, treat it as the start of a message
    if [[ -n "$ID" && "$ID" != ???????????????? ]]; then
        MSG="$ID $*"
        ID=""
    else
        MSG="$*"
    fi

    init_dirs; cleanup_expired

    if [[ -z "$ID" ]]; then
        local LATEST
        LATEST=$(ls -t "$REQ_DIR"/*.req 2>/dev/null | head -1) || {
            echo "sudo --adv:deny: no pending requests" >&2; exit 1
        }
        ID=$(basename "$LATEST" .req)
    fi

    local REQ="$REQ_DIR/$ID.req"
    [[ -f "$REQ" ]] || { echo "sudo --adv:deny: request [$ID] not found" >&2; exit 1; }

    local CMD PIPE AGE
    CMD=$(req_cmd "$REQ")
    PIPE="$RESP_DIR/$ID.pipe"
    AGE=$(req_age "$REQ")

    echo ""
    echo "┌─ Denying [$ID]  (${AGE}s old)"
    echo "│  Command : sudo $CMD"
    [[ -n "$MSG" ]] && echo "│  Message : $MSG"
    echo "└─ Sending denial..."

    if [[ -p "$PIPE" ]]; then
        local encoded_msg=""
        [[ -n "$MSG" ]] && encoded_msg=$(b64enc "$MSG")
        printf 'DENIED:1:%s\n' "$encoded_msg" > "$PIPE" &
        WRITE_PID=$!
        sleep 0.2
        kill "$WRITE_PID" 2>/dev/null || true
    else
        echo "  Warning: pipe missing — requester may already be gone." >&2
    fi

    rm -f "$REQ"
    echo "Denied."
}
