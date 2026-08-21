# &desc: "mountpointsResolveLeaf bash function -- live lsblk LABEL/NAME lookup for a device, label/name/auto modes, shared by every mount-entry call."

mountpointsResolveLeaf() {
  local dev="$1" mode="$2" label name
  label="$(@LSBLK_BIN@ -no LABEL "$dev" 2>/dev/null | head -n1)"
  case "$mode" in
    label)
      printf '%s' "$label"
      ;;
    name)
      name="$(@LSBLK_BIN@ -no NAME "$dev" 2>/dev/null | head -n1)"
      printf '%s' "$name"
      ;;
    auto)
      if [ -n "$label" ]; then
        printf '%s' "$label"
      else
        name="$(@LSBLK_BIN@ -no NAME "$dev" 2>/dev/null | head -n1)"
        printf '%s' "$name"
      fi
      ;;
  esac
}
