<!-- &desc: "Bug: `settings security sandbox enable|disable|state` is real, working, special-cased CLI dispatch (like bruteforceLockout) but is entirely absent from cli/registry.kdl, so it's invisible to `help`, `debug parse-cli`, and any doc generation driven by the registry -- violating the registry file's own stated contract for which commands are allowed to be dispatch-only exceptions." -->
# `sandbox enable/disable/state` undocumented -- missing from registry.kdl

## Repro (audit VM, 1.16.3 baseline)
```
cas myvault help settings security sandbox
#   network / seccomp / namespaces / rootfs / cgroups   <- no enable/disable/state listed
cas myvault settings security sandbox enable --pass "..."
# [✓] sandbox enabled for 'myvault'      <- works fine, not actually missing
cas myvault exec --pass "..." -- id
# only reachable at all because I happened to know the exact string from
# grepping src/commands/exec/mod.rs's own die!() message
```
`cli/registry.kdl`'s only children under `sandbox` are `network`,
`seccomp`, `namespaces`, `rootfs`, `cgroups` -- no `action "enable"`,
`"disable"`, or `"state"` nodes exist there at all. But
`src/commands/settings/security/sandbox/mod.rs`'s own `&desc:` tag says
plainly: "Not a plain enable/disable Feature -- ... same 'special-cased
in settings/mod.rs' shape bruteforceLockout already uses" -- and indeed
`dispatch()` handles `"enable"`/`"disable"`/`"state"` as real,
string-matched arms exactly like bruteforceLockout does.

The difference: bruteforceLockout's `enable`/`disable`/`state`/
`threshold` *are* declared in the registry (id 1314, documented in
`cli/help/1314.txt` etc per the registry excerpt), so `help` and
`debug parse-cli` both know about it. Sandbox's are not declared
anywhere in the registry, so:
- `cas help settings security sandbox` never lists them.
- `cas help settings security sandbox enable` falls through to
  unrelated help text (observed: it printed the bruteforceLockout /
  verification section instead, with no "no help topic" error either --
  a related but separate help-fallthrough oddity worth re-checking).
- `cas debug parse-cli`'s duplicate/ignored-id detector can't catch
  this class of gap at all, because that check only validates ids that
  *are* in the registry against Rust handlers -- it has no way to know
  a working Rust handler exists with zero registry node backing it.

registry.kdl's own top-of-file comment explicitly calls out that only
the bare `debug parse-cli` node and `vault`'s top-level/`exec` actions
are meant to be deliberate, documented exceptions to "everything goes
through cli_registry::resolve". `sandbox enable/disable/state` is a
third, undocumented exception that exists only by omission.

## Blast radius
Not a security hole -- it's a discoverability bug, but a serious one
for a security-focused CLI: the entire `exec` sandbox feature (the
biggest attack-surface-reduction feature in the tool) is **unreachable
by any user who only reads `cas help`**, because the gating command
that turns it on was never wired into the help system. A user follows
`cas help settings security sandbox`, sees only network/seccomp/
namespaces/rootfs/cgroups, configures all of those, then hits
`cas <vault> exec` and gets told to run a command (`sandbox enable`)
that `help` never once mentioned exists.

## Suggested fix direction
Add `action "enable"`, `"disable"`, `"state"` nodes under
`sandbox` in `cli/registry.kdl` with real `id`s and help text (matching
the `bruteforceLockout` precedent), plus corresponding
`cli/help/<id>.txt` files, so `help`/`debug parse-cli`/docs generation
all pick them up the same way. Since dispatch is already string-matched
in `sandbox/mod.rs` rather than going through `cli_registry::resolve`,
also double check whether adding registry ids here needs any dispatch
wiring change or if it's purely additive documentation (matching how
bruteforceLockout apparently already does both: registry ids point at
help text while the Rust match arm dispatch stays hand-written).
