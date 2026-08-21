<!-- &desc: "Bug: an overly-restrictive custom seccomp profile (default=deny, allow-list missing getpid/fork/wait4/kill/clone/exit_group -- exactly the scenario 'seccomp custom create' itself warns about at creation time) makes 'cas <vault> exec' fail completely silently: exit code 1, zero error text, no indication anything went wrong let alone why. src/sandbox/reaper.rs already has a specific, well-commented check for exactly this failure mode (getpid() returning -1) but it isn't reaching the user." -->
# `exec` fails silently (no error text) under a too-restrictive custom seccomp profile

## Repro (audit VM, current source)
```
cas myvault settings security sandbox enable --pass "..."
cas myvault settings security sandbox seccomp custom create hang1 --pass "..."
#   [i] 'hang1' denies by default -- make sure its allow list also covers
#       getpid, wait4, kill, fork, clone, and exit_group, which exec's own
#       sandbox supervisor needs regardless of what command is being run
cas myvault settings security sandbox seccomp set hang1 --pass "..."
cas myvault exec --pass "..." -- echo hi
#   [i] network: unrestricted -- shares the host's real network (namespaces doesn't include 'net')
#   (nothing else -- process exits with code 1, no error message at all)
```
Confirmed reproducible twice, both times: no stdout/stderr text beyond
the routine network-mode info line, exit code 1, no leftover processes
(the namespace does get torn down, so this isn't a permanent hang/
deadlock — the first apparent hang during initial testing was almost
certainly VM CPU contention from concurrent `cargo build`s elsewhere in
the same session, not a real infinite hang; the clean re-test with
`timeout -s KILL 10` completed in ~4s both times).

## Why this is surprising given the code
`src/sandbox/reaper.rs::run_as_pid1` has a deliberate, heavily-commented
check for exactly this class of problem:
```rust
let own_pid = unsafe { libc::getpid() };
if own_pid == -1 {
    // ... "if a custom seccomp profile with default=\"deny\" is active,
    // it needs to explicitly allow getpid/wait4/kill/fork/clone/
    // exit_group as well, since this sandbox's own PID1 supervisor
    // needs those, not just the command being run"
    return Err(...)
}
```
This message never appeared. Two explanations to investigate, not yet
narrowed down:
1. The seccomp filter's default action for `default = "deny"` custom
   profiles might be `SECCOMP_RET_KILL_PROCESS` rather than
   `SECCOMP_RET_ERRNO` — if so, `getpid()` doesn't *return* -1, the
   whole process is instantly killed by the kernel on the very first
   disallowed syscall, and this Rust-level check never gets a chance to
   run at all. That would mean the check in `reaper.rs` is currently
   unreachable dead code for the "default: deny, empty allow list"
   scenario it explicitly documents itself as defending against.
2. Alternatively, the filter might be getting installed *before* some
   setup step that itself needs a non-allow-listed syscall, killing the
   process earlier in `src/sandbox/mod.rs`'s setup sequence, well before
   `reaper.rs` is ever reached, in which case the fix belongs earlier in
   that sequence, and `reaper.rs`'s own check may be defending a
   different, narrower scenario than the one this repro hits.

## Blast radius
UX/reliability, not a security hole -- if anything this fails safe (the
sandbox is simply unusable, not less isolated than configured). But for
a tool whose whole differentiator is fine-grained seccomp control, a
misconfigured custom profile producing a bare, unexplained "exit 1"
directly contradicts the tool's own stated design intent (the
create-time warning proves the authors know this failure mode exists
and care about it) and would send a user debugging blind.

## Suggested fix direction
Determine which of the two explanations above is actually happening
(check the seccomp filter's configured default action for `deny` mode
in `src/sandbox/seccomp.rs`, and check whether the filter is installed
before or after every setup syscall the PID1 process itself needs to
make). If it's explanation 1 (KILL_PROCESS default action defeating the
existing error-reporting check), consider whether `default = "deny"`
should use `SECCOMP_RET_ERRNO` (returning EPERM) instead of
`SECCOMP_RET_KILL_PROCESS` for syscalls made by the sandbox's own
supervisor machinery specifically (as opposed to the user's command,
where a hard kill is arguably still the right, more secure choice) --
or, if the supervisor's own syscalls are meant to be exempted from the
custom filter entirely (installing the seccomp filter only around the
final `execvp` of the user's command, after the supervisor's own setup
syscalls are done), verify that's actually happening and fix the
ordering if it isn't. Either way, the end state should be: this
scenario produces the existing, already-written "refusing to run as
PID1 reaper: getpid() itself failed... needs to explicitly allow
getpid/wait4/kill/fork/clone/exit_group" message (or an equivalent one
reached earlier in the setup sequence), not silence.
