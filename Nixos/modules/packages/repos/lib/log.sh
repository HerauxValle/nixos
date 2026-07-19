#!/usr/bin/env bash
# &desc: "[event] message output helper, shared by every gitctl subcommand -- ok/info/warn/error, colored when stdout is a terminal."

log() {
  # $1 = event (ok/info/warn/error), $2 = message
  local event="$1" message="$2" color
  case "$event" in
    ok) color=32 ;; # green
    info) color=36 ;; # cyan
    warn) color=33 ;; # yellow
    error) color=31 ;; # red
    *) color=0 ;;
  esac
  if [[ -t 1 ]]; then
    printf '\033[%sm[%s]\033[0m %s\n' "$color" "$event" "$message"
  else
    printf '[%s] %s\n' "$event" "$message"
  fi
}
