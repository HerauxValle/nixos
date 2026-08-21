<!-- &desc: "Bug: `info`/`list` report raw file size including the 128MiB LUKS_DATA_OFFSET_MB reserve, with no distinction from the usable size the user asked for at create time, and no explanation anywhere in help text." -->
# `info`/`list` size field silently includes hidden 128MiB reserve

## Repro (in audit VM, 1.16.3 baseline)
```
cas testvault create --size 200 --pass "correcthorsebatterystaple"
# [cas] creating vault 'testvault' (200 MiB, strength=medium) ...
cas testvault info --pass "correcthorsebatterystaple"
# size    328 MiB
```

## Root cause
`src/commands/create.rs:60`: `size_arg = size + config::LUKS_DATA_OFFSET_MB`
(128 MiB) when truncating the backing file. This is presumably reserved
for `settings security headerOffset` (moving the LUKS2 header into a
hidden slot) even when that feature is disabled (default). Reasonable
design. But:

- `info.rs:60` and `list.rs:34/65` read `metadata()?.len()` (the raw
  file size, 328 MiB) and label it plain `size`, with no line anywhere
  distinguishing "usable"/requested vs "on-disk". A user who created a
  200 MiB vault and later runs `info` sees 328 MiB and has no way to
  know that's expected vs. a bug/corruption.
- `cas help create`'s `--size` description never mentions the reserve
  exists, so there's nothing to cross-reference even for a careful
  reader.
- `resize.rs` math (`used + overhead`, `luks_mb * 2048` sector math)
  should be checked for whether it's reserve-aware in both directions
  (grow and shrink) -- not verified yet, flagging as a related area to
  re-check once this is fixed.

## Blast radius
Not a security hole by itself, but a correctness/trust problem for a
vault manager specifically: a user doing capacity planning (e.g.
"do I have room for these files") gets a number that's off by a fixed
128 MiB with no explanation, and can't tell that number apart from a
genuinely corrupted/tampered file size.

## Suggested fix direction
`info`/`list` should show usable size (file size minus
`LUKS_DATA_OFFSET_MB`, or the actual LUKS2 `crypttab`/`luksDump` payload
size) as the primary `size`, optionally with on-disk size as a
secondary line. `--size` help text should mention the fixed reserve.
