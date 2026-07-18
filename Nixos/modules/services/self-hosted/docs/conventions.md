# Staying generalized

Rules distilled from actual decisions/mistakes made while building this
system, not abstract advice. Each one exists because a specific thing
happened -- read `docs/architecture.md` for the mechanisms these rules
apply to.

## Data and logic never share a file

`config/self-hosted/*` holds values. `modules/services/self-hosted/*`
holds behavior. This got violated and corrected multiple times while
this system was built:

- ComfyUI's `requireMounts` was first hand-written as a hardcoded
  `mountpoint -q` check inside `stash.nix`, then "fixed" by *deriving*
  `requireMounts` from `storage` entries with Nix logic inside the
  wiring file -- still wrong, still logic dressed as config. It only
  became correct once `requireMounts` was a real typed option, set as
  **literal data** in `config/`, with zero derivation anywhere.
- ComfyUI's node/model lists were first written inside the *module*
  directory. Config, even large config, belongs in `config/` -- size is
  a reason to split into multiple files (`nodes.nix`/`models.nix`), not
  a reason to move it into `modules/`.

If you're about to write `if`, string interpolation with real
conditional meaning, or a Nix function call inside a `config/*.nix` file
(beyond `${config.vars.identity.homeDirectory}`-style path assembly), stop --
that belongs in the module.

## Don't generalize until a second real case exists

The store/installed split, `mkDepsUpdateScript`, the `:target`/`:apply`
conventions -- none of these were designed speculatively. Each was built
after (or explicitly because of) a second concrete instance:
`mkDepsUpdateScript` was extracted into `self-hosted.nix` only once
*both* OpenWebUI and ComfyUI needed the identical pip-compile-diff-write
logic -- not preemptively when only OpenWebUI had it. The store/installed
split exists on ComfyUI because its model catalog is genuinely ~700GB
with no world where all of it is wanted at once -- it does **not** exist
on Ollama or Stash, because neither has that problem, even though
"consistency" might tempt you to add it everywhere.

Corollary: when asked "should this be generalized," the right question
isn't "could it be" but "does a second real, current need for this
already exist." Abstracting from a single example is guessing.

## Every service gets the same action vocabulary anyway -- now just `update*`

An earlier version of this section described a much larger deliberate
no-op vocabulary (`install`, `sync`, `uninstall`, `uninstall:data`
existing on every service even where there was nothing real for them to
do). That's gone -- not because the "shared vocabulary, even as a no-op"
idea was wrong, but because `install`/`sync` became fully automatic
(`preStart`/`postStart`, no manual action needed at all) and `uninstall`
became `enabled`-driven (see "Destructive vs. recoverable" below)
instead of a scriptable action, leaving nothing left to standardize as a
no-op. What survives the same reasoning today: `update`/`update:apply`
exist on *every* service, including ones with almost nothing to check
(Stash) -- a deliberate, explicit tradeoff so
`systemctl start self-hosted-<name>@<action>` never surprises you with
"unknown action" for the one action family that does still exist
everywhere.

## Never silently write; `:apply` is always separate and explicit

Every check-for-updates action defaults to print/diff-only. Writing the
result into a real source file (a `sed` edit, a lockfile move) only
happens via a distinctly-named `:apply` action, verified reachable
before being relied on (see architecture.md's "why colons" section --
`!`/`=` were tried first and don't actually work as systemd unit
characters, confirmed empirically rather than assumed). Neither the
print form nor the apply form ever triggers a rebuild or a restart --
writing a change and deploying it stay two separate, deliberate steps,
always.

If you're adding a new action that modifies anything outside of what a
service creates for itself at runtime (a `config/*.nix` file, a
lockfile, anything checked into the repo), it needs this same split:
a safe default and an explicitly-named destructive/mutating variant.

## Destructive vs. recoverable -- why uninstall isn't an action anymore

This system used to have a two-tier `mkUninstallScript` (`@uninstall`/
`@uninstall:data`), split because "delete what this service created" and
"delete the actual data it was fronting" are fundamentally different in
consequence. That mechanism is gone for good -- but a real uninstall path
exists again, deliberately redesigned rather than left missing: flipping
a service's `enabled` option to `false` and rebuilding now tears down
everything `teardownPaths` declares (default: everything under `dataDir`
except `storage`), via `mkTeardownActivationScript`. The two-tier split
from the old mechanism survives as a *data* boundary instead of two
separate actions: `teardownPaths` is exactly the "safe, disposable" tier,
and `storage` (never touched by any teardown, automated or otherwise)
is exactly the "real, precious" tier that used to need the separate
`:data` variant to reach at all.

The reason this isn't a manual *action* the way `update` is: an action
you have to remember to run separately from `enabled` would let the two
drift (a service left running with `enabled = true` but manually
"uninstalled" underneath it, or vice versa) -- tying teardown directly to
the same flag that already controls whether the service exists at all
means there's exactly one source of truth for "is this installed," not
two that can disagree.

The underlying principle is unchanged from the old mechanism: anything
that can destroy data a user can't get back must never be reachable by
an automated/scripted path, only a deliberate, by-hand `rm -rf`. What
changed is *how* that boundary gets declared -- `teardownPaths` as
explicit, service-specific data (ComfyUI's is non-empty specifically
because `dataDir` holds real generated content no `storage` entry
covers) instead of a single blanket rule assumed to be safe everywhere.

## Real filesystem paths vs. Nix store paths -- know which you need

Any script that only *reads* a file (pip-compile's input, a `diff`
baseline) can take that file as a Nix `path` -- Nix copies it into the
store, which is exactly what you want for a pure read. Any script that
*writes* to "the same file" (a `.new` sibling, a direct `sed` edit) needs
the **real, plain-string filesystem path** in the actual checkout
instead -- `${aNixPath}` resolves to a read-only `/nix/store/HASH-...`
copy, and writing there is either silently pointless (nobody will ever
look in `/nix/store` for it) or outright impossible (the store is
read-only). Every `:apply`/`update` script in this system takes both
forms as separate parameters for exactly this reason
(`requirementsLock` + `requirementsLockPath`, `configFile`, `nodesFile`)
-- if you only pass one, you'll either fail to write or write to the
wrong place.

## Verify against the real thing, not what looks right

Things that were assumed-then-found-wrong in this system: that `!`/`='
would work as systemd unit-name separators (they don't -- confirmed by
actually running `systemctl start` against a throwaway unit, not by
reading past examples); that `pip-compile`'s output would resolve
cleanly the first time (it didn't -- a real version conflict between a
node's `requirements.txt` and a protected-library floor, only found by
actually running the compile); three wrong hashes in the original node
pin list (only found by actually building the fetch derivations, not by
eval succeeding). `nixos-rebuild dry-build` succeeding means Nix accepted
the *syntax* -- it does not mean the generated bash is correct, a hash is
right, or a network call behaves the way you expect. See
`adding-a-service.md`'s "verify before calling it done" for the concrete
steps this system has always used.

## The one allowed impurity stays structurally confined

`buildFHSEnv` + hash-locked `pip install` is impure (what pip resolves
isn't a pure function of its inputs the way a Nix derivation is), and
that's accepted -- but it's fenced in exactly one way, everywhere it's
used: `execStart` never references the venv as a Nix derivation, only
`venvDir` (a plain path) is used. This means a broken lockfile can only
ever fail that service's own `preStart` (`venvEnsureScript`) -- it can
never block `nixos-rebuild switch` for the rest of the system, no matter
how badly pip resolution goes. If a future service needs something else impure
(not a venv), the same rule applies: whatever's impure must never be
something a plain `nixos-rebuild switch` depends on succeeding.
