
{ lsblk }:

# Bash function shared by every entry's ./mount-entry.nix snippet -- reads
# the disk's own LABEL/NAME live, which eval time can't reliably do (see
# ../mountpoints.nix for why). Emitted once in the activation script
# preamble, called once per entry that needs it.

''
  mountpointsResolveLeaf() {
    local dev="$1" mode="$2" label name
    label="$(${lsblk} -no LABEL "$dev" 2>/dev/null | head -n1)"
    case "$mode" in
      label)
        printf '%s' "$label"
        ;;
      name)
        name="$(${lsblk} -no NAME "$dev" 2>/dev/null | head -n1)"
        printf '%s' "$name"
        ;;
      auto)
        if [ -n "$label" ]; then
          printf '%s' "$label"
        else
          name="$(${lsblk} -no NAME "$dev" 2>/dev/null | head -n1)"
          printf '%s' "$name"
        fi
        ;;
    esac
  }
''
