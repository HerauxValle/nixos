<!-- &desc: "Tracked, deliberately-deferred gaps -- things found (usually via review/testing) that are real but weren't fixed on the spot, with why not and what a real fix needs. Not a general bug tracker; entries should be removed once actually fixed." -->
# Known issues

## `seccomp set strict` segfaults a statically linked busybox under `exec`

**Found:** live testing while verifying the seccomp custom-profile
feature (2026-08-16), unrelated to that feature itself -- reproduces
identically with the plain built-in `strict` preset on its own.

**What:** `cas <vault> exec` with `seccomp set strict` active, running a
statically linked busybox (`pkgsStatic.busybox`) inside the sandbox,
exits with code 139 (SIGSEGV) instead of running normally. `default`
preset with the same binary works fine; only `strict` (and, by
extension, anything that falls back to it, like a custom profile whose
hash check fails) triggers this. Not yet root-caused -- likely `strict`
is missing a syscall this particular musl-libc binary's startup path
needs, and the process crashes instead of cleanly failing when the
kernel returns `EPERM` for it, rather than a bug in the filter-building
code itself (the same BPF builder correctly enforces both allow and
deny lists elsewhere, confirmed via passing unit tests and the mixed-
list `exec` test in the same session this was found).

**Why it wasn't fixed on the spot:** out of scope for the session that
found it (building the named custom-profile CLI feature), and root-
causing a specific-binary-under-a-specific-preset crash needs its own
focused pass (bisecting `strict`'s syscall list, likely via `strace`
against a non-static or differently-linked test binary to see which
syscall returns EPERM right before the crash).

**What a real fix looks like:** reproduce with `--debug` and a way to
see which syscall was denied right before the crash (`strace -f` on
the *host* side watching the sandboxed process, or a deliberately
narrowed test filter to binary-search which syscall in `strict`'s list
the binary actually needs), then either add the missing syscall to
`strict` in `registry/data/seccomp-presets.toml` or confirm it's a
`busybox`-specific/musl-specific issue rather than a preset gap.

## `sandbox namespaces` `net` isolation is a stub -- unshares but never sets up connectivity

**Found:** pentest subagent review, 2026-08-16.

**What:** `settings security sandbox namespaces` lists `net` as a
namespace `exec` can isolate, and the CLI docs describe the default
active set as "everything except `net`". But the actual implementation
(`sandbox::namespaces::Flags::to_libc` in `src/sandbox/namespaces.rs`)
does nothing but pass the raw `CLONE_NEWNET` flag to `unshare(2)`. There
is no veth pair, no bridge, no loopback interface bring-up, nothing --
a fresh Linux network namespace starts with zero interfaces, not even
`lo` configured up. Confirmed live: enabling `net` in the active set
and running `exec` leaves the sandboxed process with no usable network
at all, not a properly isolated-but-functional one.

**Why it wasn't fixed on the spot:** this isn't a bug to patch, it's an
unbuilt feature -- real network namespace isolation needs its own
setup step (at minimum bringing `lo` up inside the new netns; a useful
one typically also wants a veth pair to the host with NAT, or a
deliberately fully air-gapped mode as an explicit choice) that doesn't
exist anywhere in this codebase yet. That's a real feature to design
and build, not a one-line fix alongside a QA/pentest pass.

**Practical impact today:** `exec` currently defaults to *not* isolating
the network (matches the CLI's own documented default), so nothing
currently breaks -- but it also means a sandboxed process can see and
use the real host's network interfaces (confirmed: real IPs, real
traffic counters visible from inside `exec` via `/proc/net/dev`) unless
the user manually enables `net`, and enabling it today just breaks
networking outright rather than providing isolated-but-working
connectivity. For a tool positioned around privacy-focused container/
image storage, this is worth prioritizing: "no network isolation by
default" is the wrong default for that threat model, but flipping the
default before the feature actually works would be a straight
regression for anyone using `exec` for anything network-dependent.

**What a real fix looks like:** implement actual netns plumbing before
changing any default --  bring `lo` up inside the new namespace at
minimum (`ip link set lo up` equivalent, or the raw netlink calls), and
decide + document whether the default posture for an isolated session
is "no network at all" (simplest, most private, breaks anything that
needs even DNS) or "host-NAT'd via a veth pair" (usable, more
plumbing, more attack surface to get right -- an OpenVPN-style
route/firewall mistake here would defeat the whole point). Once `net`
namespace isolation actually provides working connectivity (or a
deliberate, documented no-network mode), revisit defaulting new vaults
to network-isolated `exec` sessions.

