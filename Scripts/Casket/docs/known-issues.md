<!-- &desc: "Tracked, deliberately-deferred gaps -- things found (usually via review/testing) that are real but weren't fixed on the spot, with why not and what a real fix needs. Not a general bug tracker; entries should be removed once actually fixed." -->
# Known issues

## Tarball symlink targets aren't validated on `rootfs add`/`update --tarball`

**Found:** pentest subagent review, 2026-08-16 (see `changelog/1.10.22.md`).

**What:** `rootfs add <name> --tarball <path>` and `rootfs update <name>
--tarball <path>` extract the given tarball into `base/` via the system
`tar` command (`extract_tarball_into` in `src/commands/settings/
security/sandbox/rootfs/add.rs`). Before extracting, it only checks
that the file is a valid archive (`tar -tf`) — it never inspects what's
*inside* the archive.

A tarball can contain a symlink member whose target points outside
`base/` entirely (e.g. a member named `escape_link` pointing at `/tmp`,
or anywhere else on the host). `tar` extracts that without complaint —
`cas` never looks at symlink targets before or after extraction.

`..`-containing member *names* are already blocked, but only
incidentally: GNU `tar` itself refuses to extract a member whose path
contains `..`, regardless of what `cas` does. That's not a check this
codebase performs — it's a property of the `tar` binary being shelled
out to, and would disappear if the extraction method ever changed.

**Why it's not exploitable today (as far as tested):** once `exec`
pivot_roots into a rootfs environment, the sandboxed process only sees
paths inside the new root — the host's `/tmp` (or wherever a malicious
symlink points) typically doesn't exist from inside the sandbox at all,
since the mount namespace has already switched roots by the time
anything runs. The dangling symlink mostly just sits there, inert.

**Why it's still worth fixing properly:** that containment depends
entirely on namespace/pivot_root isolation working correctly in every
case, forever. It's the same *class* of bug as the path-traversal issue
fixed in 1.10.22 (`rootfs::validate_name`) — just one layer further in
(tarball contents instead of the CLI-supplied environment name). A
future bug in the pivot_root step, or any future code path that reads
rootfs contents *before* pivoting (e.g. some inspection/verification
feature), would turn this back into a real path-escape primitive.

**Why it wasn't fixed on the spot:** a correct fix needs to parse
`tar -tvf`'s member list, identify which entries are symlinks, and
reject any whose target resolves outside `base_dir` — while still
*allowing* symlinks that stay inside, which real distro rootfs
tarballs use constantly and structurally (e.g. Alpine/Debian's
`/bin -> usr/bin`, `/lib -> usr/lib`). A naive fix (reject all
symlinks) would break every legitimate preset tarball `rootfs add
--preset` fetches. That's real, careful work, not a one-line patch —
it needed more care than the other three fixes shipped alongside it in
1.10.22, so it was documented here instead of rushed.

**What a real fix looks like:** in `extract_tarball_into` (`add.rs`),
after the existing `tar -tf` validity check, run `tar -tvf` (or a
proper tar-reading approach) and for each symlink-type member, resolve
its target relative to where it would land inside `base_dir`, then
reject (`die!`) if that resolved path would escape `base_dir` — the
same containment-check shape `rootfs::default_target` already uses for
the `default` symlink (canonicalize + compare against the expected
parent). Absolute-target symlinks (`-> /anything`) should be rejected
outright; relative-target symlinks need the actual resolution check.
