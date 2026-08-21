#!/usr/bin/env bash
# penetration/script.sh — SD test runner
# Usage: script.sh [suite]
# Suites: all, imports, cli, image, rules, modes, cleanup
set -uo pipefail

SD="sd"
APP_DIR="$HOME/Applications/SimpleDocker"
IMG_NAME="sd_test_$$"
IMG_PATH="$APP_DIR/$IMG_NAME.img"
PASS=0; FAIL=0
SUITE="${1:-all}"

log()  { echo "$1"; }
ok()   { log "  PASS $1"; ((PASS++)) || true; }
fail() { log "  FAIL $1"; ((FAIL++)) || true; }

check() {
    local desc="$1" expect="$2"; shift 2
    local out; out=$("$SD" "$@" 2>&1) || true
    echo "$out" | grep -q "$expect" && ok "$desc" || fail "$desc (got: $(echo "$out" | head -c 120))"
}
check_fail() {
    local desc="$1" expect="$2"; shift 2
    local out; out=$("$SD" "$@" 2>&1) || true
    echo "$out" | grep -q "$expect" && ok "$desc" || fail "$desc — expected '$expect' (got: $(echo "$out" | head -c 120))"
}

SD_ROOT=$(dirname "$(realpath "$(which sd)")")

# ── suites ────────────────────────────────────────────────────────────────────

suite_imports() {
    log "[ imports ]"
    python3 - << PYEOF 2>&1 && ok "all imports resolve" || fail "import error"
import sys
sys.path.insert(0, '$SD_ROOT')
from lib.variables.general import TMP_BASE, IMG_FOLDERS, TERMINAL_NAMES
from lib.variables.colors import c, CYAN
from cli.commands import register
from core.settings import get_rule
print('ok')
PYEOF
}

suite_cli() {
    log "[ cli basics ]"
    check_fail "sd alone NO_CMD"        "NO_CMD"   
    check      "sd help shows commands" "create"   -n help
    check_fail "unknown cmd errors"     "UNKNOWN"  notacommand
    check_fail "set invalid value"      "INVALID"  set rule DEFAULT_MODE invalid
    check_fail "set unknown rule"       "UNKNOWN"  set rule FAKERULE foo
}

suite_image() {
    log "[ image lifecycle ]"
    mkdir -p "$APP_DIR"
    local out
    out=$($SD create image "$APP_DIR" -name "$IMG_NAME" 2>&1) || true
    echo "$out" | grep -q "created" && ok "create image" || fail "create image (got: $out)"

    out=$($SD select "$IMG_NAME" 2>&1) || true
    echo "$out" | grep -q "selected" && ok "select by name" || fail "select by name (got: $out)"

    sleep 1
    MNT=$(ls -t /tmp/simpleDocker/sessions/* 2>/dev/null | head -1 | xargs cat 2>/dev/null || echo "")
    [ -d "$MNT/.cache" ]              && ok ".cache exists"              || fail ".cache missing (mnt=$MNT)"
    [ -d "$MNT/.tmp/tables" ]         && ok ".tmp/tables exists"         || fail ".tmp/tables missing"
    [ -f "$MNT/config/rules.jsonc" ]  && ok "rules.jsonc copied to img"  || fail "rules.jsonc missing"
}

suite_rules() {
    log "[ rules ]"
    check "list rules works"        "DEFAULT_MODE"  list rules
    check "list rules shows source" "default"       list rules

    local out
    out=$($SD set rule DEFAULT_MODE verbose 2>&1) || true
    echo "$out" | grep -q "set" && ok "set rule works" || fail "set rule (got: $out)"

    out=$($SD list rules 2>&1) || true
    echo "$out" | grep -q "override" && ok "rule shows as override" || fail "override not showing"

    out=$($SD unset rule DEFAULT_MODE 2>&1) || true
    echo "$out" | grep -q "unset" && ok "unset rule works" || fail "unset rule (got: $out)"

    check_fail "unset again RULE_NOT_SET" "RULE_NOT_SET" unset rule DEFAULT_MODE
}

suite_modes() {
    log "[ modes ]"
    local out
    out=$($SD -n which image 2>&1) || true
    echo "$out" | grep -qv "╭" && ok "-n verbose no borders" || fail "-n still showing borders"

    out=$($SD which image 2>&1) || true
    echo "$out" | grep -q "╭" && ok "default mode shows table" || fail "default mode no table"
}

suite_cleanup() {
    log "[ cleanup ]"
    local out
    out=$($SD close "$IMG_NAME" 2>&1) || true
    echo "$out" | grep -q "closed" && ok "close img" || fail "close img (got: $out)"

    out=$($SD delete image "$IMG_PATH" 2>&1) || true
    echo "$out" | grep -q "deleted" && ok "delete img" || fail "delete img (got: $out)"
}

# ── run ───────────────────────────────────────────────────────────────────────

log "=== SD penetrate [$SUITE] $(date) ==="
log "project: $SD_ROOT"
log ""

case "$SUITE" in
    all)
        suite_imports
        log ""
        suite_cli
        log ""
        suite_image
        log ""
        suite_rules
        log ""
        suite_modes
        log ""
        suite_cleanup
        ;;
    imports)  suite_imports ;;
    cli)      suite_cli ;;
    image)    suite_image ;;
    rules)    suite_rules ;;
    modes)    suite_modes ;;
    cleanup)  suite_cleanup ;;
    *)
        echo "unknown suite: $SUITE"
        echo "valid: all, imports, cli, image, rules, modes, cleanup"
        exit 1
        ;;
esac

log ""
log "=== $PASS passed, $FAIL failed ==="