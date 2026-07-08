#!/usr/bin/env bash
# lib/live.sh -- watch for incoming requests and interactively approve/deny.

do_live() {
    init_dirs

    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  sudo --adv:live  -- waiting for requests  (Ctrl+C to stop) │"
    printf "│  Auto-deny after %ds\n" "$TIMEOUT"
    echo "└─────────────────────────────────────────────────────────────┘"

    while true; do
        cleanup_expired

        for F in "$REQ_DIR"/*.req; do
            [[ -f "$F" ]] || continue
            local ID
            ID=$(basename "$F" .req)
            [[ -f "$SEEN_DIR/$ID" ]] && continue
            touch "$SEEN_DIR/$ID"

            local CMD AGE TTL REQ_USER
            CMD=$(req_cmd "$F")
            AGE=$(req_age "$F")
            TTL=$(req_ttl "$F")
            REQ_USER=$(read_field "$F" USER)

            echo ""
            echo "┌─ Incoming request [$ID]"
            echo "│  From    : $REQ_USER"
            echo "│  Command : sudo $CMD"
            echo "│  Age     : ${AGE}s   (auto-deny in ${TTL}s)"
            echo "└─"

            local ANSWER=""
            read -r -t "$TTL" -p "  Approve? [y/N] " ANSWER || {
                echo ""
                echo "  (timed out -- auto-denying)"
                ANSWER="n"
            }

            rm -f "$SEEN_DIR/$ID"
            local PIPE="$RESP_DIR/$ID.pipe"

            if [[ "$ANSWER" =~ ^[Yy]$ ]]; then
                local OUT="$OUT_DIR/$ID.out" ERR="$OUT_DIR/$ID.err" EXIT_CODE=0
                echo "  Running: sudo $CMD"
                "$REAL_SUDO" bash -c "$CMD" > "$OUT" 2> "$ERR" || EXIT_CODE=$?
                echo "  Done (exit $EXIT_CODE) -- sending result back."
                printf 'APPROVED:%d\n' "$EXIT_CODE" > "$PIPE" &
                sleep 0.2; kill $! 2>/dev/null || true
            else
                echo "  Denied."
                printf 'DENIED:1\n' > "$PIPE" &
                sleep 0.2; kill $! 2>/dev/null || true
            fi

            rm -f "$F"
        done

        sleep 1
    done
}
