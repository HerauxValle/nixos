<!-- &desc: "Installation/ reference -- disko design decisions, every bug hit while building/testing format.sh in VMs (with root cause), and a reproducible recipe for testing it again." -->

# Installation/ -- design decisions, bugs found, how to test again

This covers `../Nixos/partitioning.nix`, `setup.sh`, `format.sh`, and the
top-level `../install.sh` dispatcher. For the specific record of wiring
disko into the real `nixosConfigurations.herauxvalle` (separate from this
folder), see `../Nixos/docs/disko-wiring-verification.md`.

## Why any of this exists

The original repo-root `install.sh` only ever handled an *already*-
partitioned, already-booted system (symlink `/etc/nixos`, seed the
password). There was no declarative record of the actual disk layout,
and no way to reproduce it for a reinstall without doing everything by
hand (`sgdisk`/`cryptsetup`/`mkfs` typed interactively). `partitioning.nix`
+ `format.sh` fill that gap using disko, without touching how the
*already-installed* system boots today.

---

## Design decisions in `Nixos/partitioning.nix`

- **Reference-only by default.** Not in `configuration.nix`'s imports.
  Wired into the real `nixosConfigurations.herauxvalle` in `flake.nix`
  with `disko.enableConfig = false` -- present and buildable (so the
  *whole* real config can be dry-built with disko in the mix), but
  contributes nothing to `fileSystems`/`boot.initrd.luks.devices`/
  `swapDevices`. `hardware-configuration.nix` stays the only live
  source of truth for those until that's deliberately changed.

- **`device` is read from `$DISKO_TARGET_DEVICE`**, not hardcoded. It
  used to be a literal `/dev/disk/by-id/usb-ASMT_2462_NVME_...` string
  -- the exact serial of one specific USB-NVMe enclosure, which meant
  the config could only ever target that one physical disk. Same
  pattern as `passwordFile` below: `builtins.getEnv`, throws a clear
  error if unset. `format.sh` is the only thing that sets this, after
  asking which disk to target and confirming twice.

- **`passwordFile` is read from `$DISKO_ROOT_KEYFILE`**, never a
  literal path. Nothing in this committed file ever points at real key
  material. At real install time, export it to wherever the actual
  keyfile is mounted under the live installer.

- **Every UUID is pinned** (ESP PARTUUID, ESP vfat volume ID, LUKS
  PARTUUID, LUKS UUID, btrfs label+UUID) to match the live system
  exactly -- so a reinstall onto the *same* physical disk reproduces it
  closely enough that `hardware-configuration.nix`'s by-uuid references
  keep resolving without regenerating that file. On genuinely different
  hardware you'd normally drop these and let disko generate fresh
  random ones instead (`mkfs`/`cryptsetup` don't care what disk they're
  told to stamp a given UUID onto) -- reusing them across two
  *simultaneously connected* disks would cause `by-uuid` collisions,
  though that's not a failure mode on its own, just a "know this if it
  ever happens" gotcha.

- **The LUKS `device` field is deliberately NOT pinned** to the live
  system's actual `boot.initrd.luks.devices."root".device` value
  (`/dev/disk/by-uuid/80b7960d-...`). Tried it -- breaks a real format.
  See "Bug 3" below. It's left at disko's own default
  (`/dev/disk/by-partuuid/<the pinned partition uuid>`), which exists
  immediately after `sgdisk` creates the partition, unlike a LUKS
  payload UUID which only exists after the LUKS header is written.
  Functionally identical (same physical partition), just not the same
  string `hardware-configuration.nix` currently has.

- **`initrdUnlock = true`** on the LUKS content block. This makes disko
  contribute `boot.initrd.luks.devices."root".device` (the by-partuuid
  path above). `../Nixos/modules/boot/luks2/` separately contributes
  `.keyFile`/`.keyFileSize` onto that *same* option -- different
  sub-fields, so the module system merges them without conflict.
  Verified both by evaluation (merged result matches the live system's
  `keyFile`/`keyFileSize` exactly) and by an actual VM boot using the
  real `mount-usb-key.service` mechanism (not disko's own
  `settings.keyFile`) to unlock it.

- **Subvolume `mountOptions` are empty lists**, not `[ "subvol=@" ]`
  etc. disko auto-appends `subvol=<name>` itself -- an explicit one
  produced a harmless-but-wrong doubled option in early drafts.

- **`@swap` is declared with no `mountpoint`.** It's a real, currently
  inert subvolume that already exists on the live disk
  (`swapDevices = []` in `hardware-configuration.nix`) -- included so a
  reinstall recreates the exact same subvolume set, unused or not.

- **Scope is just `sda`** (the actual NixOS-managed disk). Deliberately
  excludes the data drives (already declared in
  `Nixos/config/system/mountpoints.nix`, no partitioning complexity to
  own), the Ventoy/VirtualKeys USB, and the separate Windows dual-boot
  NVMe.

---

## Design decisions in the scripts

- **`install.sh` (repo root) is a flag-required dispatcher.** No
  default action -- `--setup` or `--format`, anything else prints usage
  and exits 1. This is deliberate: nothing destructive should ever be
  reachable by just running the script bare.

- **`setup.sh`** is the old repo-root `install.sh`, moved verbatim
  except for its path computation (`SCRIPT_DIR` -> `REPO_ROOT`, now one
  level up since it lives in `Installation/`).

- **`format.sh` asks for the disk, nothing else.** It does not locate,
  generate, or prompt for the keyfile -- that's `$DISKO_ROOT_KEYFILE`,
  required to already be exported, matching `partitioning.nix`'s own
  safety check. Keeping this script single-purpose (like
  `Scripts/Secrets/cmd/passwd.sh` only asking for one thing) rather
  than bundling a second interactive flow felt safer than inventing new
  prompting behavior that wasn't asked for.

- **Multiple independent confirmations, not one.** Picking the wrong
  disk here is unrecoverable, so: (1) pick from a by-id list, (2) type
  the *resolved* path back exactly, (3) after the format/mount scripts
  are built (still nothing touched), type `WIPE` in caps. Any wrong
  answer at any stage aborts cleanly with nothing touched -- verified
  live, not assumed (see testing section).

- **Builds via the real flake, not `diskoConfigurations`.**
  `nix build "$REPO_ROOT#nixosConfigurations.herauxvalle.config.system.build.format"`
  -- since disko is already wired into the real `nixosConfigurations`
  (inertly, `enableConfig = false`), `system.build.format`/`.mount` are
  generated unconditionally regardless of that flag (disko's own
  `module.nix` merges `cfg.devices._scripts {...}` into `system.build`
  outside the `enableConfig` gate). No need for the separate
  `diskoConfigurations.herauxvalle` flake output for this -- that one's
  still useful standalone for schema validation, but this script
  doesn't need it.

---

## Bugs found while testing (chronological, root cause + fix)

Two separate VM rehearsals were built: one testing the underlying
disko mechanism end-to-end (format -> install -> reboot -> real
USB-keyfile unlock), one testing `format.sh` itself (the actual
interactive script, not just the Nix derivations it calls). Bugs below
are tagged which rehearsal found them.

**[install rehearsal] Bug 1 -- test disk too small.**
`virtualisation.emptyDiskImages`'s default test disk was too small to
fit the real config's fixed 5G ESP. `sgdisk` failed outright
("Could not create partition"). Fixed by explicitly sizing the disko
target disk (12G is plenty for an empty test install).

**[install rehearsal] Bug 2 -- targeted the wrong disk entirely.**
Pointed disko at `/dev/vda` -- which is the VM's own live installer
root disk, the one it's actively booted from. Disko tried to
repartition a disk out from under the running system: GPT corruption
warnings, "device or resource busy" on `mkfs`. Root cause: disko's own
test harness (`lib/tests.nix`) deliberately reserves `vda` for the
installer and only ever targets `vdb`+ for exactly this reason -- missed
that convention on the first attempt. Fixed by using `vdb` for the
disko target and shifting the simulated USB to `vdc`.

**[install rehearsal] Bug 3 -- LUKS `device` pinned to a path that
doesn't exist yet.** Originally pinned the LUKS content's `device` to
the live system's actual `/dev/disk/by-uuid/80b7960d-...` (the LUKS
payload's own UUID), reasoning "match it exactly for byte-identical
output." `cryptsetup luksFormat` failed: "Device does not exist or
access denied." Root cause: that UUID only exists *after*
`cryptsetup luksFormat` writes it into the header -- referencing it
*during* format is a chicken-and-egg problem. Fixed by leaving `device`
at disko's own default (by-partuuid, exists immediately after `sgdisk`
creates the partition) -- see `partitioning.nix`'s own comment on this.
This is the mismatch documented in `docs/disko-wiring-verification.md`.

**[install rehearsal] Bug 4 -- the "reboot" just restarted the
installer again.** After `machine.shutdown()`, calling `machine.start()`
a second time just re-boots the *same* installer VM image on its own
`vda` -- completely bypassing the disko-managed disk. The apparent
"success" (reaching `multi-user.target` in ~14s) was meaningless: it
was the trivial ext4 installer environment, not the real target system.
Root cause: NixOS test machines don't automatically know to boot from a
different disk on restart. Fixed by adapting disko's own
`create_test_machine` pattern -- a fresh QEMU invocation that
deliberately excludes the installer's own `vda`, so the persistent
disks renumber (`vdb`->`vda`, `vdc`->`vdb`) and OVMF actually finds the
real installed bootloader.

**[install rehearsal] Bug 5 -- `cryptsetup` missing from the installed
system's PATH.** `cryptsetup status root` failed with `command not
found`-shaped output. `pkgs.cryptsetup` had only been added to the
*installer* environment's `environment.systemPackages`, not the
`installedSystem` module actually being tested. Fixed by adding it
there too.

**[install rehearsal] Bug 6 -- wrong `findmnt` output assumption.**
Asserted on `subvol=` appearing in `findmnt -o OPTIONS`. It doesn't --
`findmnt` shows the active subvolume as `device[/@path]` in the
`SOURCE` column instead. Fixed the assertions to match reality (and
confirmed the real mount state first, rather than guessing a second
pattern).

**[format.sh rehearsal] Bug 7 -- no network inside the test VM.**
`format.sh`'s own `nix build "$REPO_ROOT#nixosConfigurations..."` failed
trying to fetch nixpkgs from github -- test VMs are deliberately
network-isolated. Mounting the host's `/nix/store` (`mountHostNixStore`)
makes the *files* visible, but the guest's own nix daemon won't trust
them as valid without them being registered in *its own* local
database. Fixed with `nix-store --load-db < $(pkgs.closureInfo
{ rootPaths = [...]; })/registration` inside the test, registering the
flake's inputs before running the script.

**[format.sh rehearsal] Bug 8 -- registering the wrong device value.**
First attempt pre-built `system.build.format`/`.mount` on the host
using a placeholder `$DISKO_TARGET_DEVICE`, assuming the guest's
*dependency closure* would be the same regardless of the exact device
string. It's not: a different device value produces a genuinely
different derivation, and building any *new* derivation from scratch
(even a trivial shell script) needs the full build-time toolchain, not
just what was registered. Fixed in two steps: (1) ran a cheap,
discovery-only VM pass first to find the *real* udev-assigned
`/dev/disk/by-id/virtio-<serial>` name (confirmed:
`virtio-disko-test-target`) rather than guessing, (2) used that exact
value for the host-side pre-build too, so the guest's own `nix build`
resolves to the identical, already-registered derivation.

**[format.sh rehearsal] Bug 9 -- build-time toolchain not covered by
runtime closures.** Even with matching device values, the guest still
tried to build `python-3.14.4`/`glibc-2.42`/`stdenv-linux-no-cc` from
source. Root cause: `pkgs.closureInfo`'s `rootPaths` captures a
derivation's *runtime* reference closure (what the built output
actually uses at runtime) -- `writeShellApplication`'s own build-time
environment (`stdenvNoCC`, used to run its `checkPhase`) isn't part of
that, since the *finished* script doesn't runtime-depend on a C
compiler or Python. Registering the full `system.build.toplevel`
closure didn't help either, for the same reason. Fixed by explicitly
including `pkgs.stdenvNoCC`/`pkgs.stdenv`/`pkgs.python3Minimal` as
extra `rootPaths`.

None of bugs 7-9 were bugs in `format.sh` itself -- the script worked
correctly on the very first real run once the VM could actually execute
`nix build` at all. They're recorded here because they'll recur for
*any* future test that runs `nix build` inside an isolated VM, not just
this one.

---

## How to test this again

### Testing the underlying disko mechanism (format, mount, subvolumes, real boot)

1. Write a `pkgs.testers.nixosTest` with:
   - `nodes.machine` importing `disko.nixosModules.disko`,
     `enableConfig = false`, `devices = <your test disko config>.disko.devices`
     (device forced to `/dev/vdb`, **never** `/dev/vda`)
   - `virtualisation.emptyDiskImages` sized to actually fit your
     partition layout (check the math, don't trust the framework
     default)
   - a second disk simulating the VirtualKeys USB if testing the real
     boot-time unlock path (ext4, `LABEL=VirtualKeys`, `root.key`
     written with a **test-only** secret, never the real one)
2. In the test script: build+run `system.build.format`/`.mount`
   directly (or drive `format.sh` itself, see below), install the real
   target system (`nix-store --load-db` the closure, `nix-env -p
   .../system --set`, `switch-to-configuration boot`), shut down.
3. Reboot using a **custom QEMU invocation that excludes `vda`** (copy
   the `create_booted_machine` pattern from `format-script-test.nix`'s
   git history / this repo's scratch work, or disko's own
   `lib/tests.nix`) -- a plain second `machine.start()` reboots the
   installer again, not your target system.
4. Assert on real, observable state: `dmsetup info -c` for the LUKS
   UUID, `findmnt -D` for `device[/@subvol]` mount sources (not
   `OPTIONS`), `findmnt -no FSTYPE /boot`.

### Testing `format.sh` itself (the actual interactive script)

1. Copy the repo into the test's Nix closure (`builtins.path { path =
   /home/herauxvalle/Dotfiles; }`) so `$REPO_ROOT` inside the guest
   resolves to something real. `format.sh` never writes into
   `$REPO_ROOT`, so a read-only store path is fine.
2. Give the disko target disk an **explicit serial**
   (`driveConfig.deviceExtraOpts.serial = "some-test-name"`) so it gets
   a real `/dev/disk/by-id/` entry -- `format.sh` won't accept a bare
   `/dev/vdX`.
3. Run a **cheap discovery-only pass first** (boot, `ls -la
   /dev/disk/by-id/`, nothing else) to confirm the *actual* udev name
   (`virtio-<serial>`) rather than assuming it.
4. Pre-build, on the host, with `DISKO_TARGET_DEVICE` set to that exact
   discovered value (not a placeholder) and `DISKO_ROOT_KEYFILE` set to
   a throwaway test path: `system.build.format`, `system.build.mount`,
   `system.build.toplevel`, and explicitly `pkgs.stdenvNoCC` /
   `pkgs.python3Minimal`. Feed all of them into one
   `pkgs.closureInfo { rootPaths = [...]; }`.
5. In the test script, before running `format.sh`: `nix-store --load-db
   < ${offlineClosure}/registration`.
6. Feed `format.sh` real stdin (`printf` the three answers, redirect
   into the script) -- don't bypass its prompts, that's the point of
   testing the script and not just the derivations.
7. Assert on the same real state as above, plus that the script's own
   printed output matches what a human would actually see.

### General discipline (learned the hard way earlier this session)

- **Check `free -h` before any VM/heavy-eval build, and again after.**
  This machine has zero swap configured -- a burst of memory pressure
  from stacked `import <nixpkgs> {}` evals or unmonitored subprocess
  loops caused a real hard freeze once, requiring a physical reboot.
- **Always run heavy builds with `run_in_background: true` and wait for
  the completion notification** -- don't poll, don't chain `sleep`.
- **Any subprocess-driving test/differential script needs an explicit
  timeout per call**, plus a hard-kill of the whole process group on
  timeout (not just the direct child) -- a single hung call with no
  timeout is indistinguishable from a frozen machine from the outside.
- **Do a cheap `nix eval --raw --expr '...drvPath'` pass before every
  real `nix-build`.** Every eval-level mistake in this session (missing
  args, wrong option names, coercion errors) was caught this way in
  seconds instead of burning a multi-minute VM build first.
