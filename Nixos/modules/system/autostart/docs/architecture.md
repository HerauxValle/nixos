# autostart -- how it all works

<!-- &desc: "Explains why one root systemd unit per job replaces the old manifest/run.py/sudoers engine." -->

Replaces `~/Projects/Autostart` (`smg`): a JSON manifest, a threaded
Python runner (`run.py`), a hand-generated `startup-manifest.service`,
and a hand-generated `/etc/sudoers.d/autostart-jobs` fragment. All of
that engine is gone -- what it did is now either a real systemd
primitive or doesn't need to exist at all.

## One job, one unit

Each `config.vars.system.autostart.jobs.<id>` becomes its own
`systemd.services."autostart@<id>"` (see `autostart.nix`). The `@` is
just a naming convention, borrowed from `self-hosted`'s
`mkActionService` -- these are NOT instances of a real systemd template.
A genuine template would mean a single shared `autostart@.service` file,
and `nixos-rebuild switch` can only diff whole files: changing one job's
`cmd` would make switch-to-configuration reload every currently-running
job, not just the one that changed. Separate concrete units avoid that
entirely -- only the job that actually changed is ever touched.

## No sudo, no `--user`, no password, ever

Every job is a plain root **system** service. Root is what a system unit
runs as by default -- no `sudo` in `cmd`, no sudoers fragment, no
dependency on any keyfile/drive being mounted, no interactive prompt on
boot. A job needing the real logged-in graphical session (a media-player
client, say) isn't part of this schema at all -- it's a plain,
independent `systemd.user.services` entry elsewhere, wired to
`graphical-session.target` on its own terms. Trying to fold that case
into this schema is what kept adding fields that didn't belong here;
it's simply out of scope.

## execStart / execRestart / execStop -> ExecStart= / ExecReload= / ExecStop=

`execRestart` maps to `ExecReload=`, and every unit sets
`reloadIfChanged = true` -- so when a job's own config changes,
`nixos-rebuild switch` calls `systemctl reload` on it instead of a full
stop+start. `ExecReload=` is always defined (see
`lib/mk-autostart-dispatch.nix`), even for jobs with no `execRestart`,
so reload always has something correct to do:

1. `execRestart` set -> run it.
2. Else, `execStop` and `execStart` both set -> run `execStop`, then `execStart`.
3. Else, `execStart` set -> just run it.
4. Else -> nothing.

A manual `systemctl restart autostart@<id>` still does systemd's own
plain stop-then-start (that's what `restart`, as opposed to `reload`,
always means) -- the cascade above is specifically the rebuild path.

## `dependsOn`

Resolved lazily, at runtime, inside each job's own script: before
running its `cmd`, a job calls `systemctl <verb> autostart@<dep>` for
every id in that action's `dependsOn`, same verb as the action currently
running. That only works because `lib/mk-autostart-order.nix` has
already proven, at eval time, that the graph has no cycle and every
referenced id is a real, enabled job -- a bad graph fails
`nixos-rebuild switch` via `config.assertions` before anything is built,
never a partial apply.

## `systemctl restart autostart` vs `autostart@<id>`

Every job's unit sets `partOf = [ "autostart.target" ]`. Stopping or
restarting `autostart.target` cascades to every job that names it in
`partOf` -- so `systemctl restart autostart` (the target) restarts
everything, the same "one init, one lever" `smg` used to be, while
`autostart@<id>` still targets exactly one.

## No teardown script

Flipping `config.vars.system.autostart.enabled` to `false` means no
`autostart@*` units are declared in the next generation at all --
switch-to-configuration already stops and removes units that existed in
the old generation but vanished from the new one. Nothing here holds any
data that needs cleaning up the way a self-hosted service's `dataDir`
does, so there's nothing to write a teardown activation script for.
