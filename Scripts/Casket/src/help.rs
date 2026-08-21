// &desc: "Hand-written help text — the global overview and one page per action — shown by `cas help [action]`, `-h`, `--help`, and with no arguments. `show` checks the KDL-driven registry tree (src/cli_registry) first for any path that resolves there, falling through to this file's static `topic_text` table for everything not yet migrated -- see cli/registry.kdl's own doc comment for which subtree that currently is."
use crate::cli_registry::{self, Resolved, TreeNode};
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
  cas debug <subcommand>
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
  tampered  check ransomwareProtection/verify_required/zeroize/
            bruteforceLockout against the last passphrase-verified write

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

  exec      drop a shell (or run one command) sandboxed inside the
            vault's own mount -- requires settings security sandbox
            enable first:
              exec                run $SHELL
              exec -- <cmd> ...   run one command, no shell

GLOBAL
  list          show all vaults found nearby
  all close     close every open vault on this machine
  debug         dev/introspection tools, no vault needed -- `cas help debug`
  --version     print the cas version (also -V, or `cas version`)

OPTIONS
  --pass "..."      passphrase (you will be prompted if not given)
  --keyfile path    path to keyfile (for open if 2FA vault)
  --no-log          suppress all output (for scripts)
  --debug           print [debug]-prefixed internal step tracing
  --size MiB        vault size for create  (default: 1024 = 1 GiB)
  --strength level  encryption strength: light / medium / hard / extreme
  --path dir        look for vaults here instead of auto-searching
  --removeKeyfile   delete: also delete the 2FA keyfile (preserved by default)
  --shred           delete: overwrite the vault file before removing it (best-effort)
  --test            create: mark the vault ephemeral -- 'close' deletes its .img

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
cas <vault> create [--size MiB] [--strength level] [--pass "..."] [--test]

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
               Leave it empty (interactively, or --pass "") to generate
               a strong random one instead. A typed passphrase gets a
               non-blocking weak-passphrase warning (real entropy/
               dictionary estimation via zxcvbn) if it looks easy to
               crack offline — it's never refused, just flagged.

  --test       Mark this vault ephemeral. 'close' (or 'toggle' closing it)
               deletes the .img automatically right after a clean close —
               no confirmation prompt, since that's the point. A keyfile
               is never auto-deleted even if 2FA is enabled on a --test
               vault, since it could be shared with another, real vault.
               For throwaway testing only; there's no way to un-mark a
               vault once created.

EXAMPLES
  cas myvault create
  cas myvault create --size 4096 --strength hard
  cas myvault create --path ~/vaults
  cas scratch create --test --pass ""
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
  [auth]         passphrase state (required/bypassed); whether a keyfile
                 is set and raw/embedded. Its exact path is hidden
                 unless --pass verifies — info needs no auth by default,
                 so showing a 2FA vault's second factor location for
                 free would collapse it toward passphrase-only
  [settings]     encryption, 2fa, backupAuto (+ keep count)
  [security]     every security feature (e.g. ransomwareProtection)
  [verification] which features currently require re-proving the
                 passphrase before they can be toggled

Each state line is the same '<name>   enabled|disabled' you'd get
running 'settings ... state' on that one setting individually.

Pass --pass to also verify the tamper-evidence HMAC (see 'cas help
tampered') and reveal the keyfile's exact path — both off by default so
info stays a fast, auth-free command.

EXAMPLE
  cas myvault info
  cas myvault info --pass "..."
"#,
        "tampered" => r#"
cas <vault> tampered [--pass "..."]

Checks whether ransomwareProtection/verify_required/zeroize/
bruteforceLockout still match the last passphrase-verified write,
using an HMAC keyed by the vault's own derived secret —
a plain hash wouldn't work here, since anyone editing the trailer could
just recompute a new plain hash over their edit too. Always resolves
and cryptographically checks a real passphrase, same as 'auth passwd'.

Reports one of:
  healthy      matches — nothing's been edited outside a verified write
  tampered     doesn't match — those settings were changed some other
               way (hand-edited trailer, a bug, migration)
  no baseline  no HMAC stored yet (a fresh vault, or one from before
               this feature existed) — not evidence of tampering

A tampered result doesn't get fixed by this command — run 'cas myvault
open', which resets those settings to their safe values automatically
and warns (bruteforceLockout resets to off, not on — see 'cas help
settings' for why). This command only reports the status.

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
    Leave the new passphrase empty (interactively, or --new-pass "") to
    generate a strong random one instead, same as 'create'. A typed
    passphrase gets a non-blocking weak-passphrase warning (real
    entropy/dictionary estimation via zxcvbn, not just a length check)
    if it looks easy to crack offline — it's never refused, just flagged.

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

  settings security sandbox network outbound enable|disable|state
    Off by default. Requires 'namespaces enable net' first. 'net' alone
    gives 'exec' an isolated network namespace with a working loopback
    only (no route out — safe, contained). Enabling 'outbound' on top of
    that sets up a real veth pair + host NAT (MASQUERADE rule) for each
    'exec' session, torn down automatically when it exits.

  settings security sandbox network inbound add|remove|list|enable|disable|state
    Off by default, independent of 'outbound'. 'add <hostPort>[:<sandboxPort>]
    [--protocol tcp|udp]' configures a host port to forward into the
    sandbox (sandboxPort defaults to hostPort); 'enable' actually turns
    forwarding on (adding a port doesn't by itself). Opens the listed
    host port(s) to whatever's listening inside the sandbox for the
    duration of each 'exec' session — anything that can reach this
    machine on those ports can reach the sandboxed process.

  Both 'outbound' and 'inbound' are the sandbox settings that touch the
  host's own routing/NAT tables, not just the sandboxed process's own
  namespace — everything else under 'sandbox' only affects the isolated
  process itself.

  settings security zeroize enable|disable
    Controls whether the derived LUKS secret is locked into RAM (mlock —
    can't get swapped to disk unencrypted while actively in use) and
    scrubbed from memory the moment it goes out of scope, instead of
    sitting in freed-but-not-overwritten memory until something else
    reuses that page. Default on; there's no real reason to disable it.

  settings security bruteforceLockout enable [--threshold N] | disable |
                                       threshold <N>
    Off by default. When on, 'open' PERMANENTLY DELETES the vault (no
    confirmation, no undo) after N consecutive wrong-passphrase attempts
    — default N=10, change it with --threshold on enable or 'threshold
    <N>' afterward. A correct passphrase resets the counter to 0. The
    check runs before the real unlock attempt, so an unrelated open
    failure (a busy mapper, etc.) is never miscounted as a bad guess.
    Enabling it prints a one-time warning — read it before turning this on.

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
  cas myvault settings security bruteforceLockout enable --threshold 5
  cas myvault settings security bruteforceLockout threshold 15
  cas myvault settings verification backupAuto disable --pass "..."
  cas myvault settings 2fa state
  cas myvault settings verification state
"#,
        "debug" => r#"
cas debug <subcommand>

Dev/introspection tools, no vault needed.

  parse-cli    dump the compiled-in CLI registry as ASCII, with an
               Ignored/Duplicate consistency check -- run
               'cas help debug parse-cli' for details

Unrelated to the boolean --debug flag used elsewhere (that one enables
tracing during a real vault action).
"#,
        "exec" => r#"
cas <vault> exec [-- <cmd> ...]                                [--pass "..."]

Drops a shell (or runs one command) sandboxed inside the vault's own
mount, using Linux namespaces (mount/pid/uts/ipc/user, and net if
enabled) plus pivot_root -- the sandboxed process can't see or touch
anything outside the vault's contents. Requires the vault open and
`settings security sandbox` enabled first.

  exec                run $SHELL (or /bin/sh if $SHELL isn't set)
  exec -- <cmd> ...   run exactly that command, no shell, then return

Which namespaces are active is controlled by
`settings security sandbox namespaces` -- see 'cas help settings'.

EXAMPLES
  cas myvault settings security sandbox enable --pass "..."
  cas myvault exec
  cas myvault exec -- ls -la
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
    "create", "open", "close", "toggle", "resize", "delete", "info", "tampered", "auth", "backup", "settings", "list", "all", "debug",
];

/// `path` is every token after `help`/`--help` on the command line --
/// e.g. `cas help settings security sandbox network inbound add` gives
/// `["settings", "security", "sandbox", "network", "inbound", "add"]`.
/// Checked against the registry tree first (any depth, both `bare` and
/// `vault`); anything that doesn't resolve there falls through to the
/// legacy single-token `topic_text` table unchanged, using only
/// `path[0]` the same way this function always has.
pub fn show(ctx: &Ctx, path: &[String]) {
    let Some(first) = path.first() else {
        logf!(ctx, "{HELP_GLOBAL}");
        return;
    };
    // Only a genuine *leaf* match short-circuits to the new system --
    // a Branch match (e.g. "settings", still an ancestor of the one
    // migrated subtree, not migrated itself) would otherwise shadow
    // `topic_text`'s much richer existing content for anything not
    // fully migrated yet, with only a bare, mostly-help-less child list
    // to show instead. Falling through to `topic_text` for any
    // non-leaf match keeps every not-yet-migrated path exactly as
    // informative as it already was.
    let tokens: Vec<&str> = path.iter().map(String::as_str).collect();
    let reg = cli_registry::get();
    for tree in [&reg.bare, &reg.vault] {
        match cli_registry::resolve(tree, &tokens) {
            Resolved::Leaf(node, _) => return show_leaf(ctx, node),
            // A Branch only renders from the registry if it actually
            // has a `help=` of its own -- an ancestor node that exists
            // purely for navigation (no help text ever set on it,
            // still true for anything not yet migrated) falls through
            // instead, so an unmigrated path keeps showing legacy
            // `topic_text` content rather than a sparse, help-less
            // child list.
            Resolved::Branch(node) if node.help.is_some() => return show_branch(ctx, node),
            _ => {}
        }
    }
    // `topic_text` only covers the bare topic name -- any bogus tokens
    // past it (not caught by the registry loop above, since they don't
    // belong to a migrated subtree either) must not silently fall back
    // to dumping the whole topic's help. Only a genuinely bare, one-token
    // path is eligible for the legacy table; anything longer gets the
    // same "no help topic" error the registry's own NotFound case uses,
    // just over the full typed path instead of a single token.
    if path.len() == 1 {
        match topic_text(first) {
            Some(text) => logf!(ctx, "{text}"),
            None => {
                logf!(ctx, "[x] no help topic '{first}'");
                logf!(ctx, "    available: {}", TOPICS.join(", "));
            }
        }
        return;
    }
    logf!(ctx, "[x] no help topic '{}'", tokens.join(" "));
    logf!(ctx, "    available: {}", TOPICS.join(", "));
}

/// Registry-help/<id>.txt, compiled in the same way `registry.kdl`/
/// `codes.kdl` are -- one `include_str!` per file, matched on the
/// leaf's id. A leaf with no matching file (shouldn't happen for
/// anything actually migrated) falls back to just printing its
/// one-line `help=` text instead of nothing.
fn show_leaf(ctx: &Ctx, node: &TreeNode) {
    let text = node.id.as_deref().and_then(registry_help_text);
    match text {
        Some(t) => logf!(ctx, "{t}"),
        None => logf!(ctx, "{}", node.help.as_deref().unwrap_or(&node.name)),
    }
}

/// Only reached when the branch itself has a `help=` set (see `show`'s
/// caller-side check) -- prints that, then one line per child with its
/// own short `help=`, same shape `debug parse-cli`'s tree render uses
/// for the description column.
fn show_branch(ctx: &Ctx, node: &TreeNode) {
    if let Some(h) = &node.help {
        logf!(ctx, "{h}\n");
    }
    let width = node.children.iter().map(|c| c.name.len()).max().unwrap_or(0);
    for child in &node.children {
        let help = child.help.as_deref().unwrap_or("");
        logf!(ctx, "  {:<width$}  {help}", child.name);
    }
}

/// One `include_str!` arm per migrated leaf id -- see `cli/help/*.txt`.
/// New leaves get a new arm here when they're migrated; nothing
/// dynamic/runtime-loaded, matching every other compiled-in registry
/// file.
fn registry_help_text(id: &str) -> Option<&'static str> {
    Some(match id {
        "4001" => include_str!("../cli/help/4001.txt"),
        "4002" => include_str!("../cli/help/4002.txt"),
        "4003" => include_str!("../cli/help/4003.txt"),
        "4004" => include_str!("../cli/help/4004.txt"),
        "4005" => include_str!("../cli/help/4005.txt"),
        "4006" => include_str!("../cli/help/4006.txt"),
        "4007" => include_str!("../cli/help/4007.txt"),
        "4008" => include_str!("../cli/help/4008.txt"),
        "4009" => include_str!("../cli/help/4009.txt"),
        "5001" => include_str!("../cli/help/5001.txt"),
        "1300" => include_str!("../cli/help/1300.txt"),
        "1301" => include_str!("../cli/help/1301.txt"),
        "1302" => include_str!("../cli/help/1302.txt"),
        "1303" => include_str!("../cli/help/1303.txt"),
        "1304" => include_str!("../cli/help/1304.txt"),
        "1305" => include_str!("../cli/help/1305.txt"),
        "1306" => include_str!("../cli/help/1306.txt"),
        "1307" => include_str!("../cli/help/1307.txt"),
        "1308" => include_str!("../cli/help/1308.txt"),
        "1309" => include_str!("../cli/help/1309.txt"),
        "1310" => include_str!("../cli/help/1310.txt"),
        "1311" => include_str!("../cli/help/1311.txt"),
        "1312" => include_str!("../cli/help/1312.txt"),
        "1313" => include_str!("../cli/help/1313.txt"),
        "1314" => include_str!("../cli/help/1314.txt"),
        "1315" => include_str!("../cli/help/1315.txt"),
        "1316" => include_str!("../cli/help/1316.txt"),
        "1317" => include_str!("../cli/help/1317.txt"),
        "1318" => include_str!("../cli/help/1318.txt"),
        "1319" => include_str!("../cli/help/1319.txt"),
        "2200" => include_str!("../cli/help/2200.txt"),
        "2201" => include_str!("../cli/help/2201.txt"),
        "2202" => include_str!("../cli/help/2202.txt"),
        "2203" => include_str!("../cli/help/2203.txt"),
        "2204" => include_str!("../cli/help/2204.txt"),
        "2205" => include_str!("../cli/help/2205.txt"),
        "2207" => include_str!("../cli/help/2207.txt"),
        "2208" => include_str!("../cli/help/2208.txt"),
        "2209" => include_str!("../cli/help/2209.txt"),
        "2210" => include_str!("../cli/help/2210.txt"),
        "1100" => include_str!("../cli/help/1100.txt"),
        "1101" => include_str!("../cli/help/1101.txt"),
        "1102" => include_str!("../cli/help/1102.txt"),
        "1103" => include_str!("../cli/help/1103.txt"),
        "1104" => include_str!("../cli/help/1104.txt"),
        "1105" => include_str!("../cli/help/1105.txt"),
        "1106" => include_str!("../cli/help/1106.txt"),
        "1110" => include_str!("../cli/help/1110.txt"),
        "1111" => include_str!("../cli/help/1111.txt"),
        "1112" => include_str!("../cli/help/1112.txt"),
        "1113" => include_str!("../cli/help/1113.txt"),
        "1114" => include_str!("../cli/help/1114.txt"),
        "1115" => include_str!("../cli/help/1115.txt"),
        "1116" => include_str!("../cli/help/1116.txt"),
        "1001" => include_str!("../cli/help/1001.txt"),
        "1002" => include_str!("../cli/help/1002.txt"),
        "1003" => include_str!("../cli/help/1003.txt"),
        "1004" => include_str!("../cli/help/1004.txt"),
        "1005" => include_str!("../cli/help/1005.txt"),
        "1006" => include_str!("../cli/help/1006.txt"),
        "1007" => include_str!("../cli/help/1007.txt"),
        "1008" => include_str!("../cli/help/1008.txt"),
        "1009" => include_str!("../cli/help/1009.txt"),
        "2100" => include_str!("../cli/help/2100.txt"),
        "1600" => include_str!("../cli/help/1600.txt"),
        "1601" => include_str!("../cli/help/1601.txt"),
        "1602" => include_str!("../cli/help/1602.txt"),
        "1603" => include_str!("../cli/help/1603.txt"),
        "1700" => include_str!("../cli/help/1700.txt"),
        "1701" => include_str!("../cli/help/1701.txt"),
        "1702" => include_str!("../cli/help/1702.txt"),
        "1703" => include_str!("../cli/help/1703.txt"),
        "1704" => include_str!("../cli/help/1704.txt"),
        "1705" => include_str!("../cli/help/1705.txt"),
        "1800" => include_str!("../cli/help/1800.txt"),
        "1801" => include_str!("../cli/help/1801.txt"),
        "1802" => include_str!("../cli/help/1802.txt"),
        "2206" => include_str!("../cli/help/2206.txt"),
        _ => return None,
    })
}
