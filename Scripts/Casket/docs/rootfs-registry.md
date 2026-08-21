<!-- &desc: "How `rootfs add --preset` resolves distro tarballs -- registry format, what's supported today, and how to add or fix a distro entry." -->
# Rootfs preset registry

`cas <vault> settings security sandbox rootfs add <name> --preset <distro> [<version>]`
downloads a base filesystem tarball for a named `cas exec --rootfs`
environment. Which URLs to hit, per distro, is **data, not code** —
`src/registry/data/rootfs-presets.toml`, parsed by
`src/registry/rootfs.rs`. Updating it for a new distro, or fixing a
stale URL, is a TOML edit, not a Rust change.

## Currently supported

| Distro   | Pinned version | `latest` (no version) |
|----------|----------------|------------------------|
| alpine   | yes            | yes — via a real machine-readable index |
| ubuntu   | yes            | **no** — refuses, ask for a version |
| debian   | yes (unverified)| no |

"Unverified" means the URL template looks right by inspection but
hasn't been curl'd against the real endpoint the way alpine/ubuntu's
pinned paths have. Worth checking before relying on it.

## Entry format

```toml
[alpine]
latest_index_url    = "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/{arch}/latest-releases.yaml"
latest_index_flavor = "alpine-minirootfs"
pinned_url           = "https://dl-cdn.alpinelinux.org/alpine/v{minor}/releases/{arch}/alpine-minirootfs-{version}-{arch}.tar.gz"
checksum_suffix      = ".sha256"

[ubuntu]
pinned_url         = "https://cloud-images.ubuntu.com/releases/{version}/release/ubuntu-{version}-server-cloudimg-{arch}-root.tar.xz"
checksum_suffix    = "/SHA256SUMS"
arch_names.x86_64  = "amd64"
arch_names.aarch64 = "arm64"
```

Fields, all optional except `pinned_url`:

- **`pinned_url`** (required) — template for `rootfs add <name> --preset
  <distro> <version>`. Placeholders: `{arch}`, `{version}`, `{minor}`
  (first two dot-components of `{version}` — Alpine needs
  `v3.20/releases/...` from a `3.20.3` version string).
- **`checksum_suffix`** — appended to the resolved tarball URL's
  *directory* (not the full URL) to find a checksum file, fetched and
  compared after download. Handles both a single `<hash> <filename>`
  line (Alpine/Debian's per-file `.sha256`) and a multi-line manifest
  with `*filename` markers (Ubuntu's `SHA256SUMS`) — see
  `add.rs::expected_hash`. Omit if the distro doesn't publish one; `add`
  will warn and proceed unverified rather than refuse.
- **`latest_index_url`** + **`latest_index_flavor`** — for a distro that
  publishes a real machine-readable release index (file name, version,
  and checksum in one document) instead of a fixed "latest" filename.
  Alpine's `latest-releases.yaml` lists several artifacts per release
  (minirootfs, netboot, ...); `latest_index_flavor` picks which one.
  When this resolves, no separate checksum fetch happens — the index's
  own `sha256:` field is used directly.
- **`latest_url`** — a plain, directly-downloadable "always current"
  alias URL, for a distro whose scheme doesn't need index parsing. No
  current entry uses this; it exists as a real alternative to
  `latest_index_url`, not dead code.
- **`arch_names`** — per-host-arch override table when a distro's own
  architecture naming doesn't match Rust's `std::env::consts::ARCH`
  (`x86_64`/`aarch64`). Absent host arches fall back to the unmodified
  name.

If a distro has **neither** `latest_index_url` nor `latest_url`, `rootfs
add <name> --preset <distro>` with no version explicitly refuses
("'latest' isn't available for '<distro>' yet") instead of guessing at
an unverified alias.

## Adding a new distro

1. Add a `[distroname]` block with at least `pinned_url`.
2. **Actually `curl -I` the resolved URL** before committing it — every
   entry so far had at least one wrong assumption (Alpine's "latest"
   alias doesn't have a fixed filename; Ubuntu's `current` alias 404s;
   both use `amd64`/`arm64`, not `x86_64`/`aarch64`) until checked
   against the real endpoint. Don't trust the URL shape by pattern-
   matching another distro's docs.
3. If there's a real checksum manifest, add `checksum_suffix` and check
   it parses with `add.rs::expected_hash`'s two supported shapes
   (single-line or `*filename`-prefixed multi-line). A third shape needs
   a small parser change, not a registry-only fix.
4. Run `cargo test registry::rootfs` — the structural test
   (`every_entry_resolves_cleanly`) covers any new entry automatically
   (no leftover `{placeholder}`s). Add a `_spot_check` test only if the
   entry has something worth an exact-string tripwire beyond that.
5. Test the real fetch once against a throwaway vault:
   `settings security sandbox rootfs add <tmpname> --preset <distro>
   [<version>]`, then `rootfs remove <tmpname>`.

## Why hand-parsed YAML, not a YAML crate

`parse_latest_index` (`registry/rootfs.rs`) hand-parses Alpine's flat
`-`-item, `key: value` index format instead of pulling in a YAML crate.
That's a deliberate, narrow choice for *this one document shape* — it
is not a general YAML parser and will break on nested structures,
multi-line values, or anything beyond flat scalar fields. If a future
distro's index needs real YAML, that's grounds to add a proper crate
then, not to stretch this parser to cover it.
