<!-- &desc: "On-disk byte layout of the vault metadata trailer, shared between this tool and the original Python one — no compatibility shim needed since both read/write the identical format." -->
# Vault metadata trailer format

Every `.img` file may carry a small metadata block appended after its
LUKS2 container. `cryptsetup` doesn't know it's there — it treats the
whole file as a raw block device and only ever addresses the LUKS
portion, so growing/shrinking the trailer never touches encrypted data.

## Layout

Reading from the end of the file backward:

```
[ ... LUKS2 container ... ][ JSON payload ][ 4-byte length, big-endian ][ 8-byte magic ]
                            ^-- payload_len bytes                       "IMGVLT01"
```

- **Magic**: the literal ASCII bytes `IMGVLT01`, always the last 8 bytes
  of a tagged file. Its absence means "no metadata" — a plain LUKS image,
  or one that predates this format.
- **Length**: a 4-byte big-endian `u32`, immediately before the magic,
  giving the JSON payload's byte length.
- **Payload**: that many bytes immediately before the length, parsed as
  UTF-8 JSON.

Untagged files (magic mismatch, or a file too short to hold the fixed
12-byte suffix) are treated as carrying no metadata — the same as an
empty `{}` — rather than an error.

## Fields

| Field | Type | Meaning |
|---|---|---|
| `keyfile` | string | Absolute path to the 2FA keyfile, if 2FA is enabled |
| `encrypted` | bool | `false` means the encryption-UX bypass is active |
| `_autokey` | string (base64) | The full LUKS secret, stored so `open` can skip prompting when `encrypted` is `false` |
| `backup_auto` | bool | Whether an auto-snapshot is taken on every `open` |
| `backup_auto_keep` | integer | How many auto-snapshots to retain |

All fields are optional; a vault with no 2FA and no special settings
carries an empty `{}` payload (2 bytes) plus the 12-byte suffix — 14
bytes of trailer total.

## Why no compatibility layer

This Rust implementation and the original Python one read and write the
*same* format — same magic, same big-endian length, same JSON field
names (including the `_autokey` underscore prefix). A vault created,
resized, or re-keyed by one is fully readable by the other; there's
nothing to translate. `meta.rs`'s `Meta::read/strip/write` is a
byte-for-byte port of the original's `meta_read`/`meta_strip`/`meta_write`,
verified by round-tripping a real vault's trailer through both
implementations (see `docs/porting-notes.md`).

## Write discipline

`Meta::write()` always strips any existing trailer first, then appends —
so calling it twice never stacks trailers. Every code path that calls
`Meta::strip()` before a LUKS operation restores the trailer via
`Meta::write()` on *every* exit, including failure, before returning to
the caller. See `docs/porting-notes.md` for a case where the original
Python didn't guarantee this.
