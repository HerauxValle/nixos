#!/usr/bin/env bash
# Runs nix-store --optimise. Nix's own "X freed by hard-linking" line is
# the precise figure for what this operation actually deduplicated --
# surfaced explicitly below. The store-size before/after is a separate,
# broader measurement: it reflects everything that changed in the store
# during the run, not only what optimise itself did, so it won't always
# match Nix's own number exactly. The full per-path output is too spammy
# to read live, so it's captured silently -- a single updating line shows
# it's actually progressing (not stuck), the full summary prints once done.
set -euo pipefail

before_kb=$(du -s /nix/store 2>/dev/null | cut -f1)
before_paths=$(ls /nix/store | wc -l)
start=$(date +%s)

tmp_log=$(mktemp)
trap 'rm -f "$tmp_log"' EXIT

nix-store --optimise -vv > "$tmp_log" 2>&1 &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
    lines=$(wc -l < "$tmp_log" 2>/dev/null || echo 0)
    printf "\rrunning nix-store --optimise... (%s paths processed so far)" "$lines"
    sleep 1
done
wait "$pid"
printf "\r\033[K"

end=$(date +%s)
after_kb=$(du -s /nix/store 2>/dev/null | cut -f1)
after_paths=$(ls /nix/store | wc -l)
delta_kb=$((before_kb - after_kb))

echo "before:           $((before_kb / 1024 / 1024))G, $before_paths top-level paths"
echo "after:            $((after_kb / 1024 / 1024))G, $after_paths top-level paths"
echo "store size delta: $((delta_kb / 1024 / 1024))G (whole-store, not attributable to optimise alone)"
echo "duration:         $((end - start))s"
echo
grep -E "freed by hard-linking" "$tmp_log" || echo "dedup savings: none reported (nothing new to link)"
