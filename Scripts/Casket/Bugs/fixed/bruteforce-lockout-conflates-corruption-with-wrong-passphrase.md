<!-- &desc: "CRITICAL bug: bruteforceLockout counts any cryptsetup-open failure (including header/keyslot corruption, not just a genuinely wrong passphrase) toward the deletion threshold -- filesystem bitrot can silently, irreversibly delete a vault with the correct passphrase supplied every time." -->
# bruteforceLockout deletes vaults on corruption, not just wrong guesses

## Severity: HIGH -- irreversible data loss from a non-attacker cause

## Repro (audit VM, 1.16.3 baseline)
```
cas testvault2 create --size 200 --pass correcthorsebatterystaple
cas testvault2 settings security bruteforceLockout enable --threshold 3 --pass correcthorsebatterystaple
# simulate bitrot / a bad sector / a torn write near the LUKS header --
# NOT an attacker, NOT a wrong passphrase:
dd if=/dev/urandom of=testvault2.img bs=1 count=64 seek=100000 conv=notrunc
cas testvault2 open --pass correcthorsebatterystaple
#   [!] wrong passphrase (1/3 — vault deletes at 3)
```
The passphrase supplied is byte-for-byte correct. `cryptsetup open`
fails because the keyslot/metadata region was corrupted, and cas
attributes the failure to "wrong passphrase" and increments the same
counter that leads to deletion. Three corrupted opens (or even three
transient failures -- see below) and the vault is gone, with the
"[!] wrong passphrase (1/3)" messaging actively telling the user
something false about the cause.

## Root cause (hypothesis, needs confirmation against actual source)
Whatever wraps `cryptsetup open` in `open.rs` treats any non-zero exit
/ "No key available" as equivalent to "wrong passphrase" and feeds it
into the same counter bruteforceLockout uses. `cryptsetup`'s "No key
available with this passphrase" message is genuinely ambiguous between
"passphrase is wrong" and "the keyslot data cryptsetup tried to check
the passphrase against is corrupted" -- cas needs a way to tell these
apart (e.g. `cryptsetup luksDump`/header checksum validation *before*
attempting a key-derivation-based open, or at minimum checking the
LUKS2 JSON metadata's own checksum first) rather than trusting
cryptsetup's single ambiguous error class.

## Blast radius
Any bit flip, bad sector, botched `dd`/backup restore, or interrupted
write that lands in the LUKS2 header/keyslot area (a small, fixed
region near the front of the file) turns into automatic, unconfirmable
vault deletion for anyone who has bruteforceLockout on -- a security
feature -- with zero attacker involvement. This is worse than the
threat bruteforceLockout defends against: an attacker doesn't need to
guess anything, they just need write access to a few bytes of the file
(or the storage medium needs to degrade) to nuke the vault, and an
honest user gets a misleading "wrong passphrase" message that sends
them down the wrong debugging path right before their data disappears.

## Suggested fix direction
Before counting a failed open toward the bruteforceLockout threshold,
distinguish "cryptographically wrong passphrase" from "header/keyslot
unreadable or corrupted" (e.g. via `cryptsetup luksDump --dump-json-metadata`
or checking the LUKS2 header's own checksum independent of passphrase
correctness). Only the former should count. Corruption should surface
as its own distinct error (and ideally point at `cas <vault> tampered`
or a recovery path), never silently consume a bruteforceLockout
strike. Also verify: does `tampered`'s HMAC check share this same
ambiguity?
