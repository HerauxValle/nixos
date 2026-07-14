#!/usr/bin/env bash
# Sourced by build.sh / update.sh, never run standalone -- expects
# log_debug/log_error already in scope and VENVCTL_LOCKROOT exported.
# Staged as *.lock.new first so a failed/partial pip freeze never
# clobbers a previously-good lock -- promotion is a plain mv, so it's
# atomic on any sane filesystem.

lockfile_write() {
  local name="$1" path="$2" dir new final
  dir="$VENVCTL_LOCKROOT/$name"
  new="$dir/requirements.lock.new"
  final="$dir/requirements.lock"

  mkdir -p "$dir"

  if ! "$path/bin/pip" freeze --quiet > "$new" 2>/dev/null; then
    log_error "lockfile_write: pip freeze failed for '$name', leaving previous lock untouched"
    rm -f "$new"
    return 1
  fi

  mv "$new" "$final"
  log_debug "lockfile written: $final"
}
