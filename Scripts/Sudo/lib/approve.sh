#!/usr/bin/env bash
# lib/approve.sh — approve a pending request (latest or by ID).
# Usage: do_approve [ID] [message...]

do_approve() {
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
            echo "sudo --adv:approve: no pending requests" >&2; exit 1
        }
        ID=$(basename "$LATEST" .req)
    fi

    local REQ="$REQ_DIR/$ID.req"
    [[ -f "$REQ" ]] || { echo "sudo --adv:approve: request [$ID] not found" >&2; exit 1; }

    local CMD PIPE OUT ERR EXIT_CODE AGE TTL
    CMD=$(req_cmd "$REQ")
    PIPE="$RESP_DIR/$ID.pipe"
    OUT="$OUT_DIR/$ID.out"
    ERR="$OUT_DIR/$ID.err"
    AGE=$(req_age "$REQ")
    TTL=$(req_ttl "$REQ")
    EXIT_CODE=0

    echo ""
    echo "┌─ Approving [$ID]  (${AGE}s old, ${TTL}s left)"
    echo "│  Command : sudo $CMD"
    [[ -n "$MSG" ]] && echo "│  Message : $MSG"
    echo "│  Running now — sudo password may be required."
    echo "└─"
    echo ""

    "$REAL_SUDO" bash -c "$CMD" > "$OUT" 2> "$ERR" || EXIT_CODE=$?

    echo ""
    echo "┌─ Finished [$ID]  exit=$EXIT_CODE"
    [[ -s "$OUT" ]] && echo "│  stdout : $(wc -l < "$OUT") line(s)"
    [[ -s "$ERR" ]] && echo "│  stderr : $(wc -l < "$ERR") line(s)"
    echo "└─ Forwarding result to requester..."

    if [[ -p "$PIPE" ]]; then
        # Encode message to avoid newline issues in pipe protocol
        local encoded_msg=""
        [[ -n "$MSG" ]] && encoded_msg=$(b64enc "$MSG")
        printf 'APPROVED:%d:%s\n' "$EXIT_CODE" "$encoded_msg" > "$PIPE" &
        WRITE_PID=$!
        sleep 0.2
        kill "$WRITE_PID" 2>/dev/null || true
    else
        echo "  Warning: pipe missing — requester may already be gone." >&2
        rm -f "$OUT" "$ERR"
    fi

    rm -f "$REQ"
    echo "Done."
}
