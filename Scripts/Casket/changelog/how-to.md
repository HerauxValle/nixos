<!-- &desc: "Blueprint for writing changelog entries -- read this before adding one." -->
# How to write a changelog entry

One file per version. Filename is the version, nothing else: `2.1.0.md`.
No `CHANGELOG.md`, no cumulative file — if you're editing an old
version's file, you're doing it wrong. Old entries don't change.

## Versioning

`MAJOR.MINOR.PATCH`

- **MAJOR** — an old vault or script silently gets the wrong result: a
  file format changed shape without a migration, a capability is gone
  with no replacement, or a default flips with no signal that it
  flipped. If nothing tells you the ground moved, it's major.
- **MINOR** — a command moved, a flag's default changed, or something
  new was added — but the old path still tells you what happened: it
  redirects, prints where the thing went, or the new behavior is the
  kind you'd notice (not a silent wrong answer). A new command, a new
  flag, a new feature is always minor. Old scripts get a loud heads-up
  instead of a silent surprise.
- **PATCH** — a bug fixed, nothing added or removed. Behavior that was
  supposed to happen now actually happens.

One version per unit of work that actually shipped — one feature, one
fix, one breaking change. Don't bundle three unrelated things into one
version because they happened the same day. Don't split one feature
into three versions because you found a bug in it before it ever
shipped — a bug caught and fixed before anyone used the broken version
isn't its own version, it's just how the feature ended up.

Testing-only changes (verifying something still works, no code changed)
don't get a version. Docs-only changes belong with whatever version
they document, not their own.

## What goes in an entry

Short. Bullet points. Say what changed and, if it's not obvious why,
one line on why. No summaries, no "this release introduces", no
restating the version number in prose. A person skimming ten of these
in a row should be able to tell what happened in each one in about two
seconds.

Bad:
> This release introduces a comprehensive ransomware protection
> feature that significantly enhances the security posture of the
> vault by implementing directory-level access controls.

Good:
> - added: `settings security ransomwareProtection` — locks `.casket/`
>   to root-only so a same-user attacker (e.g. ransomware) can't touch
>   snapshots

## Template

```markdown
<!-- &desc: "vX.Y.Z changelog." -->
# X.Y.Z

- added: ...
- changed: ...
- fixed: ...
- breaking: ... (only if MAJOR — say what broke and what to do instead)
```

Only include the categories you actually used. A patch release usually
only has `fixed:`. Order doesn't matter much, but put `breaking:` first
if it's there — that's the one people need to see before they upgrade.
