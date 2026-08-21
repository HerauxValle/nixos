<!-- &desc: "Bug found while verifying the resize/info fix: config::MIN_VAULT_MB (96) is below btrfs's actual minimum formattable size (~109 MiB usable), so the 'minimum vault size is 224 MiB' floor error create/resize enforce is untruthful -- a vault created or shrunk to exactly that reported floor fails on its first open with an mkfs.btrfs error, not a clean success." -->
# `MIN_VAULT_MB` floor is below what btrfs can actually format

## Repro (audit VM, current source)
```
cas v1 create --size 96 --pass "..."      # or: resize an existing vault down to 224 MiB on-disk
cas v1 open --pass "..."
#   [x] mkfs.btrfs -f -L v1 [0.2 GB] /dev/mapper/casvault_v1 failed:
#       ERROR: '/dev/mapper/casvault_v1' is too small to make a usable filesystem
#       ERROR: minimum size for each btrfs device is 114294784
```
`config::MIN_VAULT_MB = LUKS_OVERHEAD_MB(32) + 64 = 96` MiB usable
(224 MiB on-disk once `LUKS_DATA_OFFSET_MB` is added). btrfs's own
minimum is 114294784 bytes ≈ 109.03 MiB usable. So `create --size 96`
and `resize <vault> 224` (on-disk) are both accepted by cas's own
floor check with a confident "minimum vault size is 224 MiB" message,
then fail outright the moment the filesystem actually needs to be
formatted (first `open` for a fresh `create`, or immediately for an
existing vault being reformatted).

Found while independently verifying the `info`/`list`/`resize`-shrink
fix in `changelog/1.17.0.md` — not a re-appearance of that bug (no data
corruption here, it fails safe with a clean mkfs error), but a
pre-existing, separate off-by-~13-MiB floor problem in the same
`config.rs` neighborhood.

## Blast radius
Low-severity but a real trust problem for a floor check whose entire
job is "tell the user the truth about the minimum before they hit
it" — right now it doesn't, by about 13 MiB, 100% of the time at
exactly that value.

## Suggested fix direction
Raise `MIN_VAULT_MB` (or the effective floor `create`/`resize` enforce)
to comfortably clear btrfs's real minimum (114294784 bytes) plus a
safety margin -- e.g. round up to 112 or 128 MiB usable rather than 96,
so the floor is an actually-formattable value on first try, not just a
value cas's own arithmetic considers sufficient.
