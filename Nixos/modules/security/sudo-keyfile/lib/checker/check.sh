# &desc: "Sudo keyfile checker -- no-mount read of the keyfile off the raw block device (ext/FAT/NTFS/btrfs direct, others via mount fallback), SHA-256 compare against the stored hash."

set -euo pipefail

[ -f "@CONF_FILE@" ] || exit 1
[ -f "@HASH_FILE@" ] || exit 1

# shellcheck source=/dev/null
source "@CONF_FILE@"
: "${IDENT_TYPE:?}" "${IDENT_VALUE:?}" "${REL_PATH:?}"

dev="/dev/disk/by-${IDENT_TYPE}/${IDENT_VALUE}"
[ -e "$dev" ] || exit 1

fstype="$(blkid -o value -s TYPE "$dev" 2>/dev/null || true)"
[ -n "$fstype" ] || exit 1

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

content=""
case "$fstype" in
  ext2|ext3|ext4)
    content="$(debugfs -R "cat $REL_PATH" "$dev" 2>/dev/null || true)"
    ;;
  vfat|fat|msdos)
    content="$(mcopy -n -i "$dev" "::$REL_PATH" - 2>/dev/null || true)"
    ;;
  ntfs)
    content="$(ntfscat -f "$dev" "$REL_PATH" 2>/dev/null || true)"
    ;;
  btrfs)
    if btrfs restore --path-regex "^$REL_PATH\$" "$dev" "$tmpdir" >/dev/null 2>&1; then
      f="$tmpdir/$REL_PATH"
      [ -f "$f" ] && content="$(cat "$f")"
    fi
    ;;
  *)
    mnt="$tmpdir/mnt"
    mkdir -p "$mnt"
    if mount -o ro "$dev" "$mnt" >/dev/null 2>&1; then
      f="$mnt/$REL_PATH"
      [ -f "$f" ] && content="$(cat "$f")"
      umount "$mnt" >/dev/null 2>&1 || true
    fi
    ;;
esac

[ -n "$content" ] || exit 1

actual_hash="$(printf '%s' "$content" | sha256sum | cut -d' ' -f1)"
stored_hash="$(cat "@HASH_FILE@")"
[ "$actual_hash" = "$stored_hash" ] || exit 1
exit 0
