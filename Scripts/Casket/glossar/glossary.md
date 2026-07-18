<!-- &desc: "Glossary of the LUKS/btrfs/udisks domain vocabulary used throughout cas's code and docs." -->
# Glossary

**LUKS / LUKS2** — Linux Unified Key Setup, the on-disk format for
`dm-crypt` block-device encryption. LUKS2 is the current version; it's
what `cas` has always formatted new vaults as (`cryptsetup luksFormat
--pbkdf argon2id`). LUKS1 is the older format — still handled when
*reading* key-slot info (`luks::used_slots`), since a dump's exact
wording differs between the two, but never written.

**dm-crypt** — the Linux kernel's device-mapper target that does the
actual block-level encryption/decryption. `cryptsetup` is the userspace
tool that manages it; `cas` never talks to dm-crypt directly, only
through `cryptsetup`.

**Mapper / mapper device** — the decrypted block device dm-crypt exposes
at `/dev/mapper/<name>` once a LUKS container is unlocked (`cryptsetup
open`). `cas` names these `casvault_<vault-name>` (`config::MAPPER_PREFIX`).
It's this device, not the `.img` file, that actually gets mounted.

**Key slot** — one of up to 32 independent password/keyfile "sockets" a
LUKS header can hold, each able to unlock the *same* underlying volume
key. Changing a passphrase never re-encrypts your data — it writes a new
key to a free slot, verifies it, then deletes the old slot
(`luks::slot_cycle`). This is what makes passphrase changes crash-safe.

**KDF / PBKDF / Argon2id** — the key derivation function that turns a
passphrase into cryptographic key material, deliberately made slow (and
memory-hard, for Argon2id) so brute-forcing it is expensive. `cas`'s
`--strength` flag (`light`/`medium`/`hard`/`extreme`) picks the memory
cost and iteration count fed to `--pbkdf argon2id` — see
`config::Strength`.

**Vault** — this tool's unit of encryption: one `<name>.img` file (a
LUKS2 container) plus, once opened, a mount directory `<name>/` next to
it holding the decrypted btrfs filesystem inside.

**2FA / combined secret** — this tool's two-factor scheme: the actual
LUKS secret becomes `SHA256(passphrase + keyfile_bytes)` rather than the
passphrase alone (`secret::combined_secret`). Neither the passphrase nor
the keyfile alone can unlock the vault.

**Autokey / encryption-bypass** — an opt-in convenience mode
(`encryption off`) that stores the actual LUKS secret, base64-encoded,
in the vault's own metadata trailer, so `open` doesn't need to prompt.
The data is exactly as LUKS-encrypted as always; this only skips asking
for a passphrase.

**Metadata trailer** — the small JSON block `cas` appends after a
vault's LUKS2 container to remember its keyfile path,
encryption-bypass state, and backup settings. See
`docs/metadata-format.md` for the exact byte layout.

**btrfs subvolume** — a separately-snapshottable "sub-filesystem" within
a single btrfs mount. `cas backup create` makes a *readonly* subvolume
snapshot of the vault's root; `backup restore` swaps the live contents
for a snapshot's.

**udisks / udisksctl** — the userspace daemon (and its CLI) that manages
removable media and loop devices for desktop environments. `cas` uses it
for two things: auto-mounting a 2FA keyfile's removable drive
(`keyfile_mount.rs`), and registering/refreshing a vault's `.img` as a
loop device so file managers show the right size (`udisks.rs`).

**Loop device** — a virtual block device (`/dev/loopN`) backed by a
regular file, letting tools that expect a block device (like
`cryptsetup`) operate on a plain `.img` file.

**Auto-backup / auto-snapshot** — a readonly btrfs snapshot taken
automatically on every `open`, named `auto-HH:MM:SS-[DD-MM-YYYY]`, kept
up to a configurable count (`backup_auto_keep`, default 3) and pruned
oldest-first.

**Slot cycle** — the safe passphrase-rotation sequence: write the new
secret to a free slot, verify it opens the vault, only then delete the
old slot. See `luks::slot_cycle` and `docs/architecture.md`.
