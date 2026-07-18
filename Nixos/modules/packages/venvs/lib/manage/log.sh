# &desc: "Internal logging library providing color-coded print utilities conditioned on specific script verbosity levels."

#!/usr/bin/env bash
# Sourced, not executed -- guards below assume $VENVCTL_LOGLEVEL is set
# by whoever called us (venvctl or the home-manager activation script).
# debug: everything. error: only failures. silent: nothing but the final
# one-line success/error summary printed by the caller itself.

: "${VENVCTL_LOGLEVEL:=error}"

_log_dot() {
  # $1 = color code (32 green / 31 red / 33 yellow), $2 = message
  printf "  [ \033[%sm•\033[0m ] %s\n" "$1" "$2"
}

log_debug() {
  [[ "$VENVCTL_LOGLEVEL" == "debug" ]] && _log_dot 36 "$*"
  return 0
}

log_info() {
  # info is shown in debug mode only -- error mode should stay quiet
  # unless something actually failed, per the spec ("error only on
  # errors, silent hides it and only outputs success or error").
  [[ "$VENVCTL_LOGLEVEL" == "debug" ]] && _log_dot 32 "$*"
  return 0
}

log_error() {
  [[ "$VENVCTL_LOGLEVEL" == "silent" ]] && { echo "$*" >&2; return 0; }
  _log_dot 31 "$*" >&2
}

log_result() {
  # Always shown, even in silent mode -- this IS the "success or error"
  # line silent mode is allowed to keep.
  local status="$1" name="$2"
  if [[ "$status" == "ok" ]]; then
    [[ "$VENVCTL_LOGLEVEL" != "silent" ]] && _log_dot 32 "venv '$name' ok"
  else
    _log_dot 31 "venv '$name' FAILED"
  fi
}
