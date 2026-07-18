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

ACTIONS (run on a specific vault)
  create    make a new vault
  open      unlock and mount a vault so you can access your files
  close     lock the vault again
  toggle    open if closed, close if open
  info      show vault details (size, open/closed, 2fa status)
  passwd    change the passphrase
  2fa on    generate a keyfile — both passphrase AND keyfile required to open
  2fa off   remove 2FA and delete the keyfile
  encryption on/off  toggle passphrase prompt UX (vault stays encrypted on disk)
  backup    create / list / restore / delete btrfs snapshots inside the vault
  resize    grow or shrink the vault — accepts M/MiB/G/GiB/T/TiB (e.g. 20G, 500MiB)
  delete    permanently delete the vault file
  rename    rename the vault file (must be closed)

GLOBAL
  list      show all vaults found nearby
  all close close every open vault on this machine

OPTIONS
  --pass "..."      passphrase (you will be prompted if not given)
  --keyfile path    path to keyfile (for open if 2FA vault)
  --no-log          suppress all output (for scripts)
  --size MiB        vault size for create  (default: 1024 = 1 GiB)
  --strength level  encryption strength: light / medium / hard / extreme
  --path dir        look for vaults here instead of auto-searching

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
cas <vault> close

Unmounts and locks the vault. Your files are encrypted again and the
<vault> folder becomes empty. Always close vaults when done.

EXAMPLE
  cas myvault close
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

Shows a summary of the vault:
  - full path and file size
  - whether it is currently open and where
  - whether 2FA is enabled and which keyfile is used
  - number of active LUKS key slots

EXAMPLE
  cas myvault info
"#,
        "passwd" => r#"
cas <vault> passwd [--pass "..."] [--new-pass "..."] [--strength level]

Changes the passphrase. The vault must be closed first.
You will be prompted for your current passphrase, then asked for
the new one twice (to avoid typos).

Use --pass and --new-pass for fully non-interactive use (e.g. scripts).
Use --strength to re-key with a different KDF cost (light/medium/hard/extreme).
If --strength is omitted, the new slot inherits default cryptsetup settings.

This is done safely: old slot stays valid until new one is verified.
A crash mid-way cannot lock you out.

If 2FA is enabled, only the passphrase changes — the keyfile stays the same.

EXAMPLE
  cas myvault passwd --pass "old" --new-pass "new" --no-log
  cas myvault passwd --strength hard
"#,
        "2fa" => r#"
cas <vault> 2fa on  [--pass "..."]
cas <vault> 2fa off [--pass "..."]

2FA means the vault needs BOTH a passphrase AND a keyfile to open.

  2fa on
    Generates a keyfile at <vault-dir>/<name>.key (64 random bytes).
    The path is fixed — no choice. Back it up somewhere safe (USB, password
    manager, second machine). If you lose it, the vault cannot be opened.

  2fa off
    Reads the keyfile path from the vault header, disables 2FA, and deletes
    the keyfile. If the keyfile is missing at the cached path, move it back
    there first, then run 'cas <vault> 2fa off' again.

HOW IT WORKS
  The real LUKS passphrase becomes SHA256(your_passphrase + keyfile_contents).
  Neither alone can open the vault.

EXAMPLES
  cas myvault 2fa on
  cas myvault 2fa on --pass "mypassphrase" --no-log
  cas myvault 2fa off
"#,
        "backup" => r#"
cas <vault> backup create <name>   — create a readonly btrfs snapshot inside the vault
cas <vault> backup list            — list snapshots (newest first, with creation date)
cas <vault> backup restore <name>  — replace vault contents with a snapshot
cas <vault> backup delete <name>   — delete a snapshot

The vault must be open for all backup operations.
Snapshots live at /.cas-snapshots/<name> inside the vault.

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
cas <vault> delete

Permanently deletes the vault file and its keyfile (if 2FA was enabled).
The vault must be closed first.

If the keyfile is missing at the cached path, open the vault first
('cas <vault> open') so the header is verified, then close and delete.

Asks you to type the vault name to confirm. Skipped with --no-log.

EXAMPLE
  cas myvault delete
"#,
        "encryption" => r#"
cas <vault> encryption on  [--pass "..."]
cas <vault> encryption off [--pass "..."]

Toggle the passphrase-prompt UX. The vault remains LUKS-encrypted on disk
regardless of this setting — it controls how 'open' behaves.

  encryption off
    Your passphrase (hashed) is stored in the vault's trailing metadata.
    'cas <vault> open' (and toggle) will unlock without prompting.
    Useful if the vault is on a trusted machine and you want seamless access.

  encryption on  (default)
    Removes the stored key from metadata.
    'cas <vault> open' requires your passphrase as normal.

WARNING: 'encryption off' stores your LUKS key derivation material in
plaintext in the vault file's metadata. Only use this if the .img file
itself is on a trusted / already-encrypted volume.

EXAMPLES
  cas myvault encryption off
  cas myvault encryption on
  cas myvault encryption off --pass "mypass" --no-log
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
    "create", "open", "close", "toggle", "info", "passwd", "2fa", "backup", "resize", "delete", "encryption",
    "list", "all",
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
