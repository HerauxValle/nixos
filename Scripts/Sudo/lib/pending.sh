#!/usr/bin/env bash
# lib/pending.sh — list all pending broker requests.

do_pending() {
    init_dirs
    cleanup_expired

    local FOUND=0
    for F in "$REQ_DIR"/*.req; do
        [[ -f "$F" ]] || continue
        FOUND=1
        local ID CMD AGE TTL USER
        ID=$(basename "$F" .req)
        CMD=$(req_cmd "$F")
        AGE=$(req_age "$F")
        TTL=$(req_ttl "$F")
        USER=$(read_field "$F" USER)
        printf '[%s]  %3ds old  %3ds left  user=%-10s  sudo %s\n' \
            "$ID" "$AGE" "$TTL" "$USER" "$CMD"
    done

    [[ $FOUND -eq 0 ]] && echo "No pending sudo requests."
}
