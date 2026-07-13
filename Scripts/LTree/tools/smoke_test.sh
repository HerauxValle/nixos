#!/usr/bin/env bash
# smoke_test.sh -- brutal, self-contained smoke test for ltree.
#
# Builds a throwaway playground covering every known edge case (deep
# nesting, symlink cycles, dangling symlinks, unreadable files/dirs,
# unicode + binary garbage, empty files, huge files, thousands of
# small files, weird filenames, gitignore rules, empty dirs) and then
# exercises every CLI flag / -o module combination against it,
# checking exit codes, crash signals, and JSON validity.
#
# Usage: tools/smoke_test.sh [path-to-ltree-binary]
# Exit code: 0 if all checks passed, 1 otherwise.

set -u
BIN="${1:-./build/ltree}"
if [ ! -x "$BIN" ]; then
    echo "error: ltree binary not found/executable at '$BIN'" >&2
    exit 1
fi
BIN="$(readlink -f "$BIN")"

WORK="$(mktemp -d /tmp/ltree_smoke.XXXXXX)"
PG="$WORK/playground"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
FAILED_NAMES=()

# ---------------------------------------------------------------- helpers --
note()  { printf '  %s\n' "$*"; }
header(){ printf '\n== %s ==\n' "$*"; }

# run NAME -- CMD...
# Runs CMD, checks it didn't crash (no core-dump signal), records pass/fail.
run_ok() {
    local name="$1"; shift
    local out rc
    out="$("$@" 2>&1)"
    rc=$?
    if [ $rc -ge 128 ]; then
        FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
        note "FAIL  $name  (killed by signal $((rc-128)): $(kill -l $((rc-128)) 2>/dev/null))"
        printf '%s\n' "$out" | tail -5 | sed 's/^/        /'
        return 1
    fi
    PASS=$((PASS+1))
    note "ok    $name  (exit $rc)"
    return 0
}

# run_expect_fail NAME -- CMD...   (expects a clean nonzero exit, NOT a crash)
run_expect_fail() {
    local name="$1"; shift
    local out rc
    out="$("$@" 2>&1)"
    rc=$?
    if [ $rc -ge 128 ]; then
        FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
        note "FAIL  $name  (crashed instead of clean error, signal $((rc-128)))"
        return 1
    fi
    if [ $rc -eq 0 ]; then
        FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
        note "FAIL  $name  (expected nonzero exit, got 0)"
        return 1
    fi
    PASS=$((PASS+1))
    note "ok    $name  (cleanly rejected, exit $rc)"
    return 0
}

# run_json NAME -- CMD...   (checks exit ok AND stdout is valid JSON)
run_json() {
    local name="$1"; shift
    local out rc
    out="$("$@" 2>/tmp/ltree_smoke_stderr)"
    rc=$?
    if [ $rc -ge 128 ]; then
        FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
        note "FAIL  $name  (killed by signal $((rc-128)))"
        return 1
    fi
    if [ $rc -ne 0 ]; then
        FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
        note "FAIL  $name  (nonzero exit $rc)"
        return 1
    fi
    if ! printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/tmp/ltree_smoke_jsonerr; then
        FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
        note "FAIL  $name  (invalid JSON)"
        sed 's/^/        /' /tmp/ltree_smoke_jsonerr
        return 1
    fi
    PASS=$((PASS+1))
    note "ok    $name  (valid JSON)"
    return 0
}

# assert_field NAME JSON_PATH_EXPR_ON_STDIN EXPECTED_PY_BOOL_EXPR
# Runs CMD, pipes JSON to a python snippet that must print "OK" or "BAD:<msg>"
assert_json() {
    local name="$1"; local pyexpr="$2"; shift 2
    local out rc result
    out="$("$@" 2>&1)"
    rc=$?
    result="$(printf '%s' "$out" | LTREE_ASSERT_EXPR="$pyexpr" python3 -c "
import json, os, sys
expr = os.environ['LTREE_ASSERT_EXPR']
try:
    d = json.load(sys.stdin)
except Exception as e:
    print('BAD:invalid json:', e); sys.exit()
try:
    ok = eval(compile(expr, '<expr>', 'eval'), {'d': d})
    print('OK' if ok else 'BAD:assertion false')
except Exception as e:
    print('BAD:eval error:', e)
")"
    if [ $rc -ge 128 ] || [[ "$result" != OK* ]]; then
        FAIL=$((FAIL+1)); FAILED_NAMES+=("$name")
        note "FAIL  $name  ($result, exit=$rc)"
        return 1
    fi
    PASS=$((PASS+1))
    note "ok    $name"
    return 0
}

# ------------------------------------------------------- build playground --
build_playground() {
    mkdir -p "$PG"
    cd "$PG" || exit 1

    mkdir -p basic
    printf 'line1\nline2\nline3\n' > basic/three_lines.txt
    printf 'no_trailing_newline' > basic/no_trailing_nl.txt
    : > basic/empty.txt
    printf '\n\n\n' > basic/only_newlines.txt

    mkdir -p unicode
    printf 'héllo wörld 日本語 emoji \xf0\x9f\x9a\x80\xf0\x9f\x94\xa5\nsecond läne\n' > unicode/utf8.txt
    printf '\xff\xfe\x00\x01binarygarbage\x00\x02' > unicode/binary_garbage.bin

    local p="deep"
    mkdir -p "$p"
    for i in $(seq 1 60); do p="$p/d$i"; mkdir -p "$p"; done
    echo "bottom" > "$p/bottom.txt"

    mkdir -p manyfiles
    for i in $(seq 1 500); do echo "f$i" > "manyfiles/file_$i.txt"; done

    mkdir -p bigfile
    head -c 10000000 /dev/urandom | base64 > bigfile/big.txt

    mkdir -p symlinks/target_dir
    echo "hi" > symlinks/target_dir/f.txt
    ln -s target_dir symlinks/link_to_dir
    ln -s target_dir/f.txt symlinks/link_to_file
    ln -s /nonexistent/path symlinks/dangling_link
    ln -s ../symlinks symlinks/self_cycle

    mkdir -p perms
    echo "secret" > perms/no_read.txt
    chmod 000 perms/no_read.txt
    mkdir -p perms/no_exec_dir
    echo "inside" > perms/no_exec_dir/f.txt
    chmod 000 perms/no_exec_dir

    mkdir -p weirdnames
    touch "weirdnames/file with spaces.txt"
    touch "weirdnames/-startswithdash.txt"
    touch "weirdnames/quote'file.txt"
    touch 'weirdnames/double"quote.txt'
    touch "weirdnames/star*glob?.txt"

    mkdir -p gittest && (cd gittest && git init -q 2>/dev/null
        echo "*.log" > .gitignore
        echo "build/" >> .gitignore
        touch keep.txt ignored.log
        mkdir -p build && touch build/artifact.o)

    mkdir -p empties/e1 empties/e2/e3

    cd - >/dev/null || exit 1
}

restore_perms() {
    # so cleanup (trap rm -rf) doesn't itself fail on 000 perms
    chmod -R u+rwx "$PG" 2>/dev/null
}
trap 'restore_perms; rm -rf "$WORK"' EXIT

# ============================================================== run it ====
header "building playground at $PG"
build_playground
note "playground built: $(find "$PG" | wc -l) entries"

header "basic invocation / help / bad args"
run_ok      "help flag"                "$BIN" -h
run_ok      "no args (defaults to cwd)" bash -c "cd '$PG' && '$BIN'"
run_expect_fail "nonexistent path"      "$BIN" "$WORK/does_not_exist"
run_expect_fail "path is a file not dir" bash -c "touch '$WORK/afile' && '$BIN' '$WORK/afile'"
run_expect_fail "unknown flag"          "$BIN" "$PG" --this-flag-does-not-exist

header "tree view, all module combos"
run_ok "tree view default"             "$BIN" "$PG"
run_ok "tree view -d dirs only"        "$BIN" "$PG" -d
run_ok "tree view LINES"               "$BIN" "$PG" -o LINES
run_ok "tree view CHARS"               "$BIN" "$PG" -o CHARS
run_ok "tree view TOTAL"               "$BIN" "$PG" -o TOTAL
run_ok "tree view FILES"               "$BIN" "$PG" -o FILES
run_ok "tree view PERMISSIONS"         "$BIN" "$PG" -o PERMISSIONS
run_ok "tree view SIZE"                "$BIN" "$PG" -o SIZE
run_ok "tree view DATE"                "$BIN" "$PG" -o DATE
run_ok "tree view EXT"                 "$BIN" "$PG" -o EXT
run_ok "tree view HASH (fast)"         "$BIN" "$PG" -o HASH
run_ok "tree view HASH (crypto)"       "$BIN" "$PG" -o HASH --cryptographic
run_ok "tree view DEBUG"               "$BIN" "$PG" -o DEBUG
run_ok "tree view DEBUG,DIFF ordering" "$BIN" "$PG" -o DEBUG,DIFF
run_ok "tree view ALL modules at once" "$BIN" "$PG" -o LINES,CHARS,TOTAL,FILES,PERMISSIONS,SIZE,DATE,EXT,HASH,DEBUG
run_ok "no-colour flag"                "$BIN" "$PG" --no-colour
run_ok "no-color (US spelling)"        "$BIN" "$PG" --no-color
run_ok "unknown -o module (should warn, not crash)" "$BIN" "$PG" -o BOGUS_MODULE

header "depth limiting"
run_ok "max depth 0"     "$BIN" "$PG" -L 0
run_ok "max depth 1"     "$BIN" "$PG" -L 1
run_ok "max depth 3"     "$BIN" "$PG" -L 3
run_ok "max depth 100 (beyond tree depth)" "$BIN" "$PG" -L 100
run_ok "max depth attached form -L2" "$BIN" "$PG" -L2
run_ok "negative depth (treated as unlimited?)" "$BIN" "$PG" -L -1

header "exclude patterns"
run_ok "exclude single glob"        "$BIN" "$PG" --exclude "*.txt"
run_ok "exclude multiple"           "$BIN" "$PG" --exclude "manyfiles,*.bin"
run_ok "exclude with path sep"      "$BIN" "$PG" --exclude "symlinks/target_dir"
run_ok "exclude= form"              "$BIN" "$PG" --exclude=basic
run_ok "exclude quoted spaces"      "$BIN" "$PG" --exclude "\"file with spaces.txt\""
run_ok "gitignore flag"             "$BIN" "$PG/gittest" --gitignore
assert_json "gitignore actually excludes ignored.log" \
    "not any(c['name']=='ignored.log' for c in d.get('tree',d).get('children',[]))" \
    "$BIN" "$PG/gittest" --gitignore -j

header "JSON output + validity"
run_json "json default"              "$BIN" "$PG" -j
run_json "json with all modules"     "$BIN" "$PG" -j -o LINES,CHARS,TOTAL,FILES,PERMISSIONS,SIZE,DATE,EXT,HASH,DEBUG
run_json "json dirs only"            "$BIN" "$PG" -j -d
run_json "json depth limited"        "$BIN" "$PG" -j -L 2
run_json "json DEBUG"                "$BIN" "$PG" -j -o DEBUG
assert_json "root hash present when -o HASH" \
    "d.get('tree',d).get('hash') is not None" \
    "$BIN" "$PG" -j -o HASH
assert_json "total.files matches real count roughly" \
    "d['total']['files'] > 0" \
    "$BIN" "$PG" -j -o TOTAL
assert_json "debug block present in json when -o DEBUG" \
    "'debug' in d and d['debug']['files_scanned'] > 0" \
    "$BIN" "$PG" -j -o DEBUG
assert_json "debug block absent from json without -o DEBUG" \
    "'debug' not in d" \
    "$BIN" "$PG" -j
assert_json "debug block has expected timing/memory keys" \
    "all(k in d['debug'] for k in ('wall_clock_seconds','scan_seconds','peak_rss_kb','heap_arena_bytes','tree_memory_bytes_estimate','hash_algo','pid'))" \
    "$BIN" "$PG" -j -o DEBUG

header "hash correctness / determinism"
H1="$("$BIN" "$PG/basic" -j -o HASH | python3 -c 'import json,sys; print(json.load(sys.stdin)["tree"]["hash"])')"
H2="$("$BIN" "$PG/basic" -j -o HASH | python3 -c 'import json,sys; print(json.load(sys.stdin)["tree"]["hash"])')"
if [ "$H1" = "$H2" ] && [ -n "$H1" ] && [ "$H1" != "None" ]; then
    PASS=$((PASS+1)); note "ok    hash is deterministic across runs ($H1)"
else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("hash determinism"); note "FAIL  hash determinism (H1=$H1 H2=$H2)"
fi
echo "extra_byte" >> "$PG/basic/three_lines.txt"
H3="$("$BIN" "$PG/basic" -j -o HASH | python3 -c 'import json,sys; print(json.load(sys.stdin)["tree"]["hash"])')"
git -C "$PG" 2>/dev/null >/dev/null || true
if [ "$H3" != "$H1" ]; then
    PASS=$((PASS+1)); note "ok    hash changes when content changes"
else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("hash change detection"); note "FAIL  hash did not change after content edit"
fi
# revert
sed -i '$ d' "$PG/basic/three_lines.txt" 2>/dev/null

header "--save-output and -o DIFF roundtrip"
run_ok "save-output default location" "$BIN" "$PG/basic" --save-output
run_ok "save-output custom dir"       bash -c "mkdir -p '$WORK/snapdir' && '$BIN' '$PG/basic' --save-output='$WORK/snapdir'"
run_ok "diff with no prior snapshot (should not crash)" "$BIN" "$PG/manyfiles" -o DIFF
run_ok "diff after a snapshot exists" bash -c "'$BIN' '$PG/basic' --save-output >/dev/null && '$BIN' '$PG/basic' -o DIFF"
echo "changed content" > "$PG/basic/three_lines.txt"
run_ok "diff detects a real change"   bash -c "'$BIN' '$PG/basic' -o DIFF" # should exit clean, just marks diffs
assert_json "save-output snapshot never contains debug block" \
    "'debug' not in d" \
    bash -c "mkdir -p '$WORK/dbgsnap' && '$BIN' '$PG/basic' -o DEBUG --save-output='$WORK/dbgsnap' >/dev/null 2>&1 && cat '$WORK/dbgsnap'/.ltree/*.json"

header "permission edge cases (unreadable file / unreadable dir)"
run_ok "scan tree containing unreadable file"     "$BIN" "$PG/perms"
run_ok "scan tree containing unreadable file -o HASH" "$BIN" "$PG/perms" -o HASH
run_ok "scan tree containing no-exec dir (can't list)" "$BIN" "$PG/perms/no_exec_dir"

header "symlink handling (dir, file, dangling, cyclic)"
run_ok "scan dir full of symlink variants"        "$BIN" "$PG/symlinks"
run_ok "scan symlinks with -o HASH"                "$BIN" "$PG/symlinks" -o HASH
run_ok "scan symlinks with -o PERMISSIONS,DATE"    "$BIN" "$PG/symlinks" -o PERMISSIONS,DATE
run_ok "self-referential symlink does not infinite loop" timeout 10 "$BIN" "$PG/symlinks"

header "unicode / binary content"
run_ok "scan unicode + binary garbage dir"  "$BIN" "$PG/unicode" -o CHARS,LINES
run_json "json of unicode dir stays valid"  "$BIN" "$PG/unicode" -j -o CHARS

header "weird filenames"
run_ok "scan dir with spaces/quotes/glob-chars in names" "$BIN" "$PG/weirdnames"
run_json "json of weird filenames stays valid"            "$BIN" "$PG/weirdnames" -j

header "empty dirs / empty files"
run_ok "scan nested empty dirs"   "$BIN" "$PG/empties"
run_ok "scan empty file"          "$BIN" "$PG/basic" -o LINES,CHARS

header "deep recursion (60 levels)"
run_ok "deep nesting, unlimited depth" timeout 15 "$BIN" "$PG/deep"
run_ok "deep nesting, depth-limited"   "$BIN" "$PG/deep" -L 5

header "large file (mmap stress, ~13MB text)"
run_ok "scan large file, plain"        "$BIN" "$PG/bigfile"
run_ok "scan large file, hash crypto"  "$BIN" "$PG/bigfile" -o HASH --cryptographic

header "many small files (500 files in one dir)"
run_ok "scan 500-file dir"                timeout 15 "$BIN" "$PG/manyfiles"
run_ok "scan 500-file dir with all modules" timeout 15 "$BIN" "$PG/manyfiles" -o LINES,CHARS,TOTAL,FILES,PERMISSIONS,SIZE,DATE,EXT,HASH

header "combined brutal case: everything at once"
run_ok "kitchen sink" timeout 30 "$BIN" "$PG" -o LINES,CHARS,TOTAL,FILES,PERMISSIONS,SIZE,DATE,EXT,HASH,DEBUG --gitignore --cryptographic
run_json "kitchen sink json" timeout 30 "$BIN" "$PG" -j -o LINES,CHARS,TOTAL,FILES,PERMISSIONS,SIZE,DATE,EXT,HASH,DEBUG --cryptographic

# also sweep known-dangerous real filesystem locations briefly, guarded by timeout
header "real filesystem danger zones (guarded, short timeout)"
run_ok "scan /proc/cpuinfo-ish tree shallow" timeout 15 "$BIN" /proc -L 1
run_ok "scan /sys shallow (MMIO / SIGILL regression guard)" timeout 20 "$BIN" /sys -L 2 -o HASH

# ============================================================ summary =====
header "SUMMARY"
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [ $FAIL -gt 0 ]; then
    echo "  failed checks:"
    for n in "${FAILED_NAMES[@]}"; do echo "    - $n"; done
    exit 1
fi
echo "  ALL CHECKS PASSED"
exit 0
