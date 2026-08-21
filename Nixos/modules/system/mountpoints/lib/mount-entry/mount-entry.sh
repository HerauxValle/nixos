# &desc: "mountpointsWarn/mountpointsMountEntry bash functions -- per-entry leaf resolution, mkdir/mount/chown, blocking-vs-warn on failure; called once per device entry."

mountpointsWarn() {
  local blocking="$1" key="$2" fmt="$3"
  shift 3
  if [ "$blocking" = "1" ]; then
    # shellcheck disable=SC2059
    printf "\033[0;31merror: modules/system/mountpoints: device.$key: $fmt\033[0m\n" "$@" >&2
    mountpointsFailed=1
  else
    # shellcheck disable=SC2059
    printf "\033[0;33mwarning: modules/system/mountpoints: device.$key: $fmt\033[0m\n" "$@" >&2
  fi
}

mountpointsMountEntry() {
  local dev="$1" mode="$2" literalLeaf="$3" blocking="$4" key="$5" uuid="$6" at="$7" hasOwner="$8" owner="$9"

  if [ ! -e "$dev" ]; then
    mountpointsWarn "$blocking" "$key" "UUID $uuid (-> $at) not found -- disk likely not attached, mount skipped for now."
    return
  fi

  local leaf
  if [ "$mode" = "literal" ]; then
    leaf="$literalLeaf"
  else
    leaf="$(mountpointsResolveLeaf "$dev" "$mode")"
  fi

  if [ -z "$leaf" ]; then
    mountpointsWarn "$blocking" "$key" "UUID $uuid -- could not resolve a name (no label?) under $at, mount skipped for now."
    return
  fi

  local target="$at/$leaf"
  @MKDIR_BIN@ -p "$target"
  if ! @MOUNTPOINT_BIN@ -q "$target"; then
    if ! @MOUNT_BIN@ "$dev" "$target"; then
      mountpointsWarn "$blocking" "$key" "failed to mount UUID $uuid at \"%s\"." "$target"
    fi
  fi

  if [ "$hasOwner" = "1" ]; then
    if @MOUNTPOINT_BIN@ -q "$target"; then
      @CHOWN_BIN@ -- "$owner" "$target"
    fi
  fi
}
