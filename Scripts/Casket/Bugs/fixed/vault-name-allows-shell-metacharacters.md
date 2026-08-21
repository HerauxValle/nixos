<!-- &desc: "Low/moderate: vault-name validation only blocks '/', '\\', NUL, '.', '..' -- it allows backticks, quotes, $(), ;, |, spaces, etc. cas itself never shells out unsafely (Command::new, no sh -c, confirmed clean), but the resulting filenames/mapper-adjacent strings are a landmine for any external script (backup wrappers, cron jobs) that naively embeds a vault name in a shell command." -->
# vault name accepts shell metacharacters

## Repro (audit VM, 1.16.3 baseline)
```
cas 'vault"`touch' create --size 200 --pass x
# [✓] vault created: /root/inject/vault"`touch.img   <- literal, on-disk
```
Confirmed **not** exploitable against `cas` itself: `src/proc.rs`
exclusively uses `std::process::Command::new(program)` with argv arrays
(checked every call site, lines 177/214/233/245) -- no `sh -c`/shell
interpolation anywhere, so backticks/`$()`/`;`/`|` in a vault name are
inert as far as cas's own subprocess calls go.

## Blast radius (real but indirect)
The name validation (`must be non-empty and can't contain '/', '\',
a null byte, or be '.'/'..'`) only defends the filesystem-path use of
the name. It doesn't defend a *second* consumer: any user-written
wrapper around `cas` (backup scripts, cron jobs, systemd units built by
string interpolation) that does something like
`eval "cas $name info"` or embeds `$name` in a shell string without
quoting. A vault named `` foo`touch /tmp/pwned` `` or `foo; rm -rf ~`
sitting on disk is a landmine for exactly that class of external
tooling, and vault names are attacker-influenceable in some real
setups (e.g. a shared/multi-user box, or restoring a vault file someone
else handed you).

## Suggested fix direction
Tighten the name validator to an explicit allow-list (alnum, `-`, `_`,
maybe `.` mid-string) rather than a deny-list of just the
filesystem-dangerous characters. This is a hardening change, not a fix
for an exploitable-today path in cas itself -- keep the blast-radius
framing honest in the changelog entry.
