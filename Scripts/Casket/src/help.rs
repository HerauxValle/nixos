// &desc: "Hand-written help text — the global overview and one page per action — shown by `cas help [action]`, `-h`, `--help`, and with no arguments."
use crate::ctx::Ctx;
use crate::logf;

const HELP_GLOBAL: &str = r#"
cas  --  encrypted vault manager
=================================
A vault is a single encrypted file (.img) that works like a folder once opened.
Everything inside is encrypted at rest — only you can read it.

USAGE
  cas <vault> <action> [options]
  cas list
  cas quit
  cas all close
  cas help <action>
  cas --version

ACTIONS (run on a specific vault)
  create    make a new vault
  open      unlock and mount a vault so you can access your files
  close     lock the vault again
  toggle    open if closed, close if open
  resize    grow or shrink the vault — accepts M/MiB/G/GiB/T/TiB (e.g. 20G, 500MiB)
  rename    rename the vault file (must be closed)
  delete    permanently delete the vault file

  info      show vault details plus every setting's enabled|disabled state
  tampered  check ransomwareProtection/verify_required/zeroize against
            the last passphrase-verified write

  auth      passphrase + keyfile identity material:
              auth passwd
              auth keyfile move|reset|embed|extract|strip|activate

  backup    create / list / restore / delete btrfs snapshots (data, not settings)

  settings  every persistent per-vault toggle, all enable|disable|state:
              settings encryption enable|disable|state
              settings 2fa enable|disable|state
              settings backup auto enable|disable|keep <N>|state
              settings security <feature> enable|disable|state
              settings verification <feature> enable|disable|state
              settings verification state   (all gated features at once)

GLOBAL
  list          show all vaults found nearby
  all close     close every open vault on this machine
  --version     print the cas version (also -V, or `cas version`)

OPTIONS
  --pass "..."      passphrase (you will be prompted if not given)
  --keyfile path    path to keyfile (for open if 2FA vault)
  --no-log          suppress all output (for scripts)
  --size MiB        vault size for create  (default: 1024 = 1 GiB)
  --strength level  encryption strength: light / medium / hard / extreme
  --path dir        look for vaults here instead of auto-searching
  --removeKeyfile   delete: also delete the 2FA keyfile (preserved by default)
  --shred           delete: overwrite the vault file before removing it (best-effort)

Output is colored automatically on a real terminal, and plain otherwise
(piped, redirected, or TERM=dumb). Set NO_COLOR=1 to force plain output.

TYPICAL FIRST USE
  cas myvault create          # create a 1 GiB vault in current folder
  cas myvault open            # open it (prompts for passphrase)
  ...put files in myvault/...
  cas myvault close           # lock it again

Run 'cas help <action>' for details on any command, with examples.
"#;

fn topic_text(topic: &str) -> Option<&'static str> {
    Some(match topic {
        "create" => r#"
cas <vault> create [--size MiB] [--strength level] [--pass "..."]

Creates a new encrypted vault. The vault is stored as a single file
called <vault>.img in the current directory (or --path).

  --size       How big the vault should be, in MiB.
               Default: 1024  (= 1 GiB). You can resize it later.

  --strength   How hard it is to brute-force your passphrase:
                 light    fastest to unlock, weakest against attacks
                 medium   good for most people  (default)
                 hard     slower to unlock, much stronger
                 extreme  very slow to unlock, very strong
               If in doubt, leave it at medium.

  --pass       Your passphrase. You will be asked if not given here.

EXAMPLES
  cas myvault create
  cas myvault create --size 4096 --strength hard
  cas myvault create --path ~/vaults
"#,
        "open" => r#"
cas <vault> open [--pass "..."] [--keyfile path]

Unlocks the vault and makes your files accessible in a folder named
<vault>, next to the .img file.

If 2FA is enabled, you need both your passphrase and keyfile.
The keyfile path is remembered automatically — you only need --keyfile
if the file has moved since last time.

EXAMPLES
  cas myvault open
  cas myvault open --keyfile /mnt/usb/my.key
"#,
        "close" => r#"
cas <vault> close [--force]

Unmounts and locks the vault. Your files are encrypted again and the
<vault> folder becomes empty. Always close vaults when done.

--force also tears down a mapper that's stuck in a broken state --
neither mounted nor cleanly closeable (e.g. left behind by a crashed
previous open/close). Without --force, "not mounted" is always treated
as "already closed" and nothing is checked further; --force actually
attempts the teardown and reports if it fails, instead of silently
no-opping. If it still fails, the mapper is genuinely wedged at the
kernel level and needs a reboot to clear -- this never touches or risks
the vault's actual encrypted data, only the runtime device mapping.

EXAMPLE
  cas myvault close
  cas myvault close --force
"#,
        "toggle" => r#"
cas <vault> toggle [--pass "..."]

Opens the vault if it's closed, closes it if it's open.
Great for assigning to a keyboard shortcut or launcher.

EXAMPLE
  cas myvault toggle
"#,
        "info" => r#"
cas <vault> info

Shows the full vault picture, grouped into sections:
  [general]      path, size, open/closed, active LUKS key slots
  [auth]         passphrase state (required/bypassed), active keyfile
                 (path, and whether it's raw or embedded)
  [settings]     encryption, 2fa, backupAuto (+ keep count)
  [security]     every security feature (e.g. ransomwareProtection)
  [verification] which features currently require re-proving the
                 passphrase before they can be toggled

Each state line is the same '<name>   enabled|disabled' you'd get
running 'settings ... state' on that one setting individually.

Pass --pass to also verify the tamper-evidence HMAC (see 'cas help
tampered') — off by default so info stays a fast, auth-free command.

EXAMPLE
  cas myvault info
  cas myvault info --pass "..."
"#,
        "tampered" => r#"
cas <vault> tampered [--pass "..."]

Checks whether ransomwareProtection/verify_required/zeroize still match
the last passphrase-verified write, using an HMAC keyed by the vault's
own derived secret — a plain hash wouldn't work here, since anyone
editing the trailer could just recompute a new plain hash over their
edit too. Always resolves and cryptographically checks a real
passphrase, same as 'auth passwd'.

Reports one of:
  healthy      matches — nothing's been edited outside a verified write
  tampered     doesn't match — those 3 settings were changed some other
               way (hand-edited trailer, a bug, migration)
  no baseline  no HMAC stored yet (a fresh vault, or one from before
               this feature existed) — not evidence of tampering

A tampered result doesn't get fixed by this command — run 'cas myvault
open', which resets those 3 settings to their most-protective values
automatically and warns. This command only reports the status.

EXAMPLES
  cas myvault tampered
  cas myvault tampered --pass "..."
"#,
        "auth" => r#"
cas <vault> auth passwd [--pass "..."] [--new-pass "..."] [--strength level]
cas <vault> auth keyfile move     <location>            [--keyfile path]
cas <vault> auth keyfile reset    [location]             [--keyfile path] [--pass "..."]
cas <vault> auth keyfile embed    <carrier-file>          [--keyfile path]
cas <vault> auth keyfile extract  <carrier-file> [location]
cas <vault> auth keyfile strip    <carrier-file>          [--pass "..."]
cas <vault> auth keyfile activate <location>              [--pass "..."]

Identity material — the passphrase and keyfile that actually unlock the
vault — as opposed to 'settings', which is behavior toggles.

  auth passwd
    Changes the passphrase. The vault must be closed first. Prompted for
    the current one, then the new one twice, unless given via
    --pass/--new-pass. Safe: old slot stays valid until the new one is
    verified, so a crash mid-way can't lock you out. If 2FA is enabled,
    only the passphrase changes — the keyfile stays the same.

A keyfile is either RAW (the whole file is the key, today's format) or
EMBEDDED (the key lives in a small tagged trailer appended to any other
file — a photo, a PDF, whatever — which keeps working as that file).
Which form a given file is in is auto-detected; you never declare it.

  auth keyfile move <location>
    Relocates the active keyfile (copy, verify, then delete the
    original — never a bare rename, since the target is often a
    different filesystem like a removable drive). Preserves its form —
    moving an embedded keyfile moves the whole carrier, doesn't flatten
    it to raw. Directory location keeps the current filename; a full
    file path uses that name instead.

  auth keyfile reset [location]
    Overwrites the active keyfile with freshly generated bytes and
    re-keys the vault's LUKS slot to match. IRREVERSIBLE — the old key
    material is gone the instant the new slot verifies; anything relying
    on the previous bytes (backups, embedded copies elsewhere) stops
    working. No location: in place, same name/path/form. Directory: keep
    the name, new raw file there. File path: that becomes the new name.

  auth keyfile embed <carrier-file>
    Copies the active keyfile's key bytes into a trailer appended to
    <carrier-file>, without disturbing its existing content. Doesn't
    activate the copy — that's 'activate', done deliberately.

  auth keyfile extract <carrier-file> [location]
    The recovery path: pulls the key bytes back out of an embedded
    carrier into a standalone raw file, if the normal keyfile is
    missing for some reason. Default location is the vault's usual
    keyfile path; refuses to overwrite anything already there.

  auth keyfile strip <carrier-file>
    The opposite of embed: removes the trailer, restoring the carrier
    to its original content. Asks you to type the vault name to confirm
    if the carrier is the vault's ACTIVE keyfile, since that would
    remove the only copy of the key material cas knows about.

  auth keyfile activate <location>
    Points the vault at a different file (raw or embedded) as its
    keyfile — without re-keying anything, so this only makes sense for a
    copy/relocation of the exact same key bytes. Verifies the passphrase
    + that file actually unlock the vault first; dies untouched if not.

All of these accept --keyfile <path> the same way 'open' does: a
one-shot override for finding the *current* keyfile, used if the cached
path is stale — you're not asked interactively when it's given.

EXAMPLES
  cas myvault auth passwd --pass "old" --new-pass "new" --no-log
  cas myvault auth keyfile move /mnt/usb/vaults/
  cas myvault auth keyfile reset
  cas myvault auth keyfile embed ~/Pictures/holiday.jpg
  cas myvault auth keyfile extract ~/Pictures/holiday.jpg
  cas myvault auth keyfile strip ~/Pictures/holiday.jpg
  cas myvault auth keyfile activate ~/Pictures/holiday.jpg
"#,
        "backup" => r#"
cas <vault> backup create <name>   — create a readonly btrfs snapshot inside the vault
cas <vault> backup list            — list snapshots (newest first, with creation date)
cas <vault> backup restore <name>  — replace vault contents with a snapshot
cas <vault> backup delete <name>   — delete a snapshot

The vault must be open for all backup operations.
Snapshots live at /.casket/snapshots/<name> inside the vault.

restore asks for confirmation (skipped with --no-log).

EXAMPLES
  cas myvault backup create before-upgrade
  cas myvault backup list
  cas myvault backup restore before-upgrade
  cas myvault backup delete before-upgrade
"#,
        "resize" => r#"
cas <vault> resize <size>

Grow or shrink the vault. Size accepts any common unit (case-insensitive):
  20G  20GB  20GiB  20g  — gigabytes
  500M 500MB 500MiB      — megabytes (default if no unit)
  1T   1TB   1TiB        — terabytes
  2048                   — bare number = MiB

  Growing is safe and instant.
  Shrinking is destructive — cas will:
    1. Check that the new size is at least 110% of the data already inside
    2. Ask you to type the vault name to confirm (skipped with --no-log)
    3. Shrink the filesystem, then the LUKS container, then the file

EXAMPLES
  cas myvault resize 2GiB
  cas myvault resize 20 GB
  cas myvault resize 512M
"#,
        "delete" => r#"
cas <vault> delete [--removeKeyfile] [--shred]

Permanently deletes the vault file. The vault must be closed first.

The keyfile (if 2FA was enabled) is preserved by default — nothing here
can tell whether some other vault's 2FA also points at the same file, so
deleting it is opt-in, not automatic. Pass --removeKeyfile to delete it
along with the vault, same as before.

--shred overwrites the .img file with random data (3 passes) before
deleting it, instead of a plain unlink. Best-effort, not a guarantee:
meaningful on a spinning disk, close to theater on an SSD — TRIM and
wear-leveling mean the overwrite likely doesn't hit the same physical
cells the original data lived on. If you need an actual guarantee on an
SSD, that comes from full-disk encryption at rest, not app-level shred.

Asks you to type the vault name to confirm. Skipped with --no-log.

EXAMPLES
  cas myvault delete
  cas myvault delete --removeKeyfile
  cas myvault delete --shred
"#,
        "settings" => r#"
cas <vault> settings encryption enable|disable|state          [--pass "..."]
cas <vault> settings 2fa enable|disable|state                 [--pass "..."]
cas <vault> settings backup auto enable|disable|keep <N>|state [--pass "..."]
cas <vault> settings security <feature> enable|disable|state   [--pass "..."]
cas <vault> settings verification <feature> enable|disable|state [--pass "..."]
cas <vault> settings verification state

Every persistent per-vault toggle lives here, all sharing enable|disable|state.
'state' prints the setting's current value as '<name>   enabled|disabled' —
the same line format 'info' rolls up for every setting at once.

  settings encryption enable|disable
    Toggle the passphrase-prompt UX. The vault remains LUKS-encrypted on
    disk regardless of this setting — it only controls how 'open' behaves.
    'disable' stores your passphrase (hashed) in the vault's metadata so
    'open'/'toggle' unlock without prompting — useful on a trusted machine.
    WARNING: 'disable' stores LUKS key derivation material in plaintext
    in the vault file's metadata. Only use this if the .img itself is on
    a trusted / already-encrypted volume.

  settings 2fa enable|disable
    2FA means the vault needs BOTH a passphrase AND a keyfile to open.
    'enable' generates a keyfile at <vault-dir>/<name>.key (64 random
    bytes, fixed path) — back it up, losing it loses the vault. 'disable'
    deletes the keyfile and reverts to passphrase-only. The real LUKS
    passphrase becomes SHA256(your_passphrase + keyfile_contents); neither
    alone can open the vault.

  settings backup auto enable|disable|keep <N>
    'enable' (optionally with --keep N, default 3) creates a timestamped
    read-only snapshot every time the vault is opened, pruning down to
    the keep count. 'disable' stops future auto-snapshots (existing ones
    are kept). 'keep <N>' changes the limit without re-enabling.

  settings security ransomwareProtection enable|disable
    Locks .casket/ (snapshots, and anything else cas keeps inside the
    vault) to root-only. Your own user account, and anything running as
    it — including ransomware — can no longer read, create, or delete
    anything in there. 'disable' hands it back to you for direct browsing.
    Protects against a same-user attacker only: root, or raw access to
    the vault's underlying block device, is outside what this can stop.

  settings security zeroize enable|disable
    Controls whether the resolved passphrase and derived LUKS secret get
    scrubbed from memory the moment they go out of scope, instead of
    sitting in freed-but-not-overwritten memory until something else
    reuses that page. Default on; there's no real reason to disable it.

  settings verification <feature> enable|disable
    Controls whether toggling <feature> (any setting above, or
    verification itself) requires re-proving the vault's real passphrase
    first — so plain root/sudo access alone can't defeat a protection.
    Disabling a currently-required verification still needs the
    passphrase, including disabling it on itself.
    Defaults: on for ransomwareProtection, backupAuto, verification, and
    auth keyfile reset (irreversible); off for encryption/2fa, which
    already re-verify the real passphrase as part of their own crypto
    operation.

EXAMPLES
  cas myvault settings encryption disable --pass "mypass" --no-log
  cas myvault settings 2fa enable
  cas myvault settings backup auto enable --keep 5
  cas myvault settings security ransomwareProtection enable --pass "..."
  cas myvault settings verification backupAuto disable --pass "..."
  cas myvault settings 2fa state
  cas myvault settings verification state
"#,
        "list" => r#"
cas list [--path dir]

Lists all .img vault files found in the current directory and up to
2 levels up. Shows name, size, open/closed state, and 2FA status.

EXAMPLES
  cas list
  cas list --path ~/vaults
"#,
        "all" => r#"
cas all close

Closes every open vault on this machine at once.
Handy before shutting down or handing over your computer.

EXAMPLE
  cas quit
  cas all close
"#,
        _ => return None,
    })
}

const TOPICS: &[&str] = &[
    "create", "open", "close", "toggle", "resize", "delete", "info", "tampered", "auth", "backup", "settings", "list", "all",
];

pub fn show(ctx: &Ctx, topic: Option<&str>) {
    match topic {
        None => logf!(ctx, "{HELP_GLOBAL}"),
        Some(t) => match topic_text(t) {
            Some(text) => logf!(ctx, "{text}"),
            None => {
                logf!(ctx, "[x] no help topic '{t}'");
                logf!(ctx, "    available: {}", TOPICS.join(", "));
            }
        },
    }
}
