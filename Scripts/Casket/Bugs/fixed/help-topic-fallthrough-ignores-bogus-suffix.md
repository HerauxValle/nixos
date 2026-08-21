<!-- &desc: "Bug found while fixing the sandbox-registry-gap bug: cas help <topic> <...bogus tail> silently dumps the entire legacy topic_text(path[0]) block instead of erroring, for any topic not yet migrated onto cli_registry (settings, auth, etc). Distinct from the 1.16.3.md fix, which only guarded a different fallthrough (a matched Branch node with no help=)." -->
# `cas help <topic> <bogus...>` silently shows the whole topic instead of erroring

## Repro (1.16.3 baseline + 1.17.0 sandbox-registry fix both still show this)
```
cas help settings totallybogus
cas help auth keyfile bogus-verb
cas help settings security sandbox bogus-verb   # before the sandbox ids existed
```
All of these dump the entire `topic_text(path[0])` block (e.g. all of
`settings`'s help) instead of any "no help topic" error.

## Root cause
`src/help.rs::show()`: when `cli_registry::resolve()` returns
`NotFound` for the typed path, the fallback unconditionally calls
`topic_text(first)` using only `path[0]` — it never looks at how many
of the remaining tokens were actually bogus, so `settings`,
`settings totallybogus`, and `settings x y z w` all render identically.

This is **not** the same bug the `changelog/1.16.3.md` entry fixed.
That fix added a `Resolved::Branch(node) if node.help.is_some()` guard
that stops a matched-but-unhelped *registry* branch from silently
showing its own raw child list. It only applies to paths that resolve
inside `cli_registry`. `settings`/`auth`/`backup` top-level topics
(and any subpath under them not yet expressed as a registry
child-with-id) go through the older `topic_text` fallback instead,
which was never touched by that fix — this is a sibling gap in the
same general "fell through to something, but too much of something"
class, not a regression.

## Blast radius
UX/discoverability only — not a security issue. A user who typos a
help path gets a wall of unrelated (but real) help text with no
indication their specific path didn't exist, which especially hurts
newer users trying to find a specific setting's help by guessing paths.

## Suggested fix direction
`topic_text` fallback should only fire when `path.len() == 1` (the bare
topic name, no trailing tokens) — any bogus suffix beyond that should
produce the same "no help topic '<path>'" error `cli_registry::resolve`
already returns for other NotFound cases, for consistency.
