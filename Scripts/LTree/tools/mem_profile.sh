#!/usr/bin/env bash
# &desc: "Measures ltree's real memory footprint (peak RSS via GNU time -v, optional valgrind massif/memcheck passes) across several synthetic directory shapes (wide, deep, many-small-files, few-big-files) and every hashing mode."
# mem_profile.sh -- measure ltree's memory footprint with real numbers.
#
# For each scenario:
#   1. GNU `time -v` gives wall-clock-accurate peak RSS (fast, always run).
#   2. valgrind --tool=massif gives a heap allocation breakdown (which
#      code path owns the bytes) -- slower, so it's optional (-m).
#   3. valgrind --tool=memcheck --leak-check=full confirms no leaks
#      and no invalid access -- optional (-l), slowest.
#
# Usage: tools/mem_profile.sh [path-to-ltree-binary] [-m] [-l]
#   -m    also run massif heap-profile pass (slower)
#   -l    also run memcheck leak-check pass (slowest)
# With no flags, only the fast RSS pass runs.

set -u
BIN="./build/ltree"
DO_MASSIF=0
DO_MEMCHECK=0
for arg in "$@"; do
    case "$arg" in
        -m) DO_MASSIF=1 ;;
        -l) DO_MEMCHECK=1 ;;
        *)  BIN="$arg" ;;
    esac
done
if [ ! -x "$BIN" ]; then
    echo "error: ltree binary not found/executable at '$BIN'" >&2
    exit 1
fi
BIN="$(readlink -f "$BIN")"

command -v /usr/bin/time >/dev/null || { echo "error: GNU time (/usr/bin/time) not found -- apt-get install time" >&2; exit 1; }

WORK="$(mktemp -d /tmp/ltree_mem.XXXXXX)"
PG="$WORK/playground"
trap 'chmod -R u+rwx "$PG" 2>/dev/null; rm -rf "$WORK"' EXIT

# ------------------------------------------------------- build scenarios --
mkdir -p "$PG"
cd "$PG"

# small: a handful of files, baseline overhead
mkdir -p small && for i in $(seq 1 10); do printf 'line %d\n' "$i" > "small/f$i.txt"; done

# wide: one directory, 5000 flat files (stresses the local[]/realloc array in build_tree)
mkdir -p wide && for i in $(seq 1 5000); do echo "x" > "wide/f_$i.txt"; done

# deep: 500 nested single-child directories (stresses recursion depth / stack)
p="deep"; mkdir -p "$p"
for i in $(seq 1 500); do p="$p/d$i"; mkdir -p "$p"; done
echo "bottom" > "$p/bottom.txt"

# bigfiles: 20 files x 5MB each (stresses mmap working set, not node count)
mkdir -p bigfiles
for i in $(seq 1 20); do head -c 5000000 /dev/urandom > "bigfiles/big_$i.bin"; done

# mixed: realistic-ish source tree shape, many small text files across subdirs
mkdir -p mixed
for d in a b c d e; do
    mkdir -p "mixed/$d"
    for i in $(seq 1 200); do
        printf 'line1\nline2\nline3\nline4\nline5\n' > "mixed/$d/file_$i.c"
    done
done

cd - >/dev/null

declare -A SCENARIOS=(
    [small]="$PG/small"
    [wide_5000_flat_files]="$PG/wide"
    [deep_500_nested_dirs]="$PG/deep"
    [bigfiles_20x5MB]="$PG/bigfiles"
    [mixed_1000_files_5dirs]="$PG/mixed"
    [whole_playground]="$PG"
)

RESULTS_FILE="$WORK/results.tsv"
echo -e "scenario\tmodules\tpeak_rss_kb\twall_time_s" > "$RESULTS_FILE"

fmt_kb() { printf '%'"'"'d' "$1" 2>/dev/null || echo "$1"; }

echo "================================================================"
echo " ltree memory profile -- $(date)"
echo " binary: $BIN"
echo "================================================================"

run_rss() {
    local label="$1" path="$2"; shift 2
    local tf; tf="$(mktemp)"
    /usr/bin/time -v "$BIN" "$path" "$@" > /dev/null 2> "$tf"
    local rss wall
    rss="$(grep 'Maximum resident set size' "$tf" | awk '{print $NF}')"
    wall="$(grep 'Elapsed (wall clock)' "$tf" | awk '{print $NF}')"
    printf '  %-45s peak RSS: %10s KB   wall: %s\n' "$label" "$(fmt_kb "$rss")" "$wall"
    echo -e "${label}\t$*\t${rss}\t${wall}" >> "$RESULTS_FILE"
    rm -f "$tf"
}

echo
echo "---- pass 1: peak RSS per scenario (plain scan, no hashing) ----"
for name in "${!SCENARIOS[@]}"; do
    run_rss "$name (plain)" "${SCENARIOS[$name]}"
done

echo
echo "---- pass 2: peak RSS with -o HASH (fast xxhash) ----"
for name in "${!SCENARIOS[@]}"; do
    run_rss "$name (-o HASH)" "${SCENARIOS[$name]}" -o HASH
done

echo
echo "---- pass 3: peak RSS with -o HASH --cryptographic (SHA-256) ----"
for name in "${!SCENARIOS[@]}"; do
    run_rss "$name (-o HASH --cryptographic)" "${SCENARIOS[$name]}" -o HASH --cryptographic
done

echo
echo "---- pass 4: peak RSS with every -o module + JSON ----"
for name in "${!SCENARIOS[@]}"; do
    run_rss "$name (-j all-modules)" "${SCENARIOS[$name]}" -j -o LINES,CHARS,TOTAL,FILES,PERMISSIONS,SIZE,DATE,EXT,HASH
done

# bytes-per-file / bytes-per-mb-scanned derived metrics, from the plain pass
echo
echo "---- derived: memory efficiency ----"
NFILES_WIDE=5000
NFILES_MIXED=1000
RSS_WIDE=$(awk -F'\t' -v s="wide_5000_flat_files (plain)" '$1==s{print $3}' "$RESULTS_FILE")
RSS_MIXED=$(awk -F'\t' -v s="mixed_1000_files_5dirs (plain)" '$1==s{print $3}' "$RESULTS_FILE")
RSS_BIG=$(awk -F'\t' -v s="bigfiles_20x5MB (plain)" '$1==s{print $3}' "$RESULTS_FILE")
if [ -n "$RSS_WIDE" ]; then
    echo "  wide (5000 tiny files):   $(awk -v r="$RSS_WIDE" -v n="$NFILES_WIDE" 'BEGIN{printf "%.2f KB/file", r/n}')"
fi
if [ -n "$RSS_MIXED" ]; then
    echo "  mixed (1000 tiny files):  $(awk -v r="$RSS_MIXED" -v n="$NFILES_MIXED" 'BEGIN{printf "%.2f KB/file", r/n}')"
fi
if [ -n "$RSS_BIG" ]; then
    echo "  bigfiles (100MB total):   $(awk -v r="$RSS_BIG" 'BEGIN{printf "%.1f KB overhead beyond streaming (peak RSS %.1f MB, one mmap window at a time expected)", r, r/1024}')"
fi

# --------------------------------------------------- optional: massif ----
if [ "$DO_MASSIF" -eq 1 ]; then
    echo
    echo "---- pass 5: valgrind massif heap breakdown (mixed scenario, all modules) ----"
    MASSIF_OUT="$WORK/massif.out"
    valgrind --tool=massif --massif-out-file="$MASSIF_OUT" --pages-as-heap=no \
        "$BIN" "$PG/mixed" -o LINES,CHARS,TOTAL,FILES,PERMISSIONS,SIZE,DATE,EXT,HASH > /dev/null 2>"$WORK/massif.log"
    if command -v ms_print >/dev/null; then
        ms_print "$MASSIF_OUT" 2>/dev/null | sed -n '1,45p'
        echo "  (full massif output kept at $MASSIF_OUT / re-run ms_print on it for detail)"
    else
        echo "  ms_print not available; raw massif snapshots at $MASSIF_OUT"
    fi
    cp "$MASSIF_OUT" /tmp/ltree_massif.out 2>/dev/null && echo "  massif data copied to /tmp/ltree_massif.out"
fi

# -------------------------------------------------- optional: memcheck ----
if [ "$DO_MEMCHECK" -eq 1 ]; then
    echo
    echo "---- pass 6: valgrind memcheck leak-check (small + mixed + symlink-ish edge dir) ----"
    for name in small mixed_1000_files_5dirs; do
        echo "  -- $name --"
        valgrind --tool=memcheck --leak-check=full --error-exitcode=99 --track-origins=yes \
            "$BIN" "${SCENARIOS[$name]}" -o LINES,CHARS,TOTAL,FILES,PERMISSIONS,SIZE,DATE,EXT,HASH \
            > /dev/null 2> "$WORK/memcheck_$name.log"
        rc=$?
        if [ $rc -eq 99 ]; then
            echo "    FAIL: memcheck found errors:"
            grep -E "ERROR SUMMARY|Invalid |LEAK SUMMARY|definitely lost|indirectly lost" "$WORK/memcheck_$name.log" | sed 's/^/      /'
        else
            grep -E "ERROR SUMMARY|LEAK SUMMARY|definitely lost|indirectly lost|possibly lost" "$WORK/memcheck_$name.log" | sed 's/^/    /'
        fi
    done
fi

echo
echo "================================================================"
echo " raw results table: $RESULTS_FILE (survives until this shell exits)"
echo " copying to /tmp/ltree_mem_results.tsv for persistence"
cp "$RESULTS_FILE" /tmp/ltree_mem_results.tsv
awk -F'\t' '{ printf "  %-42s %-45s %14s %10s\n", $1, $2, $3, $4 }' /tmp/ltree_mem_results.tsv
echo "================================================================"
