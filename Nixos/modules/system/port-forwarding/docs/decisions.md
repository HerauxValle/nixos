# Specific decisions, and what justified each

Distilled from actual back-and-forth building this module, not
abstract advice -- each one exists because a concrete question came up
or a real bug was found.

## Python scripts are concatenated Nix fragments, not a separate project

`lib/ipv6-bridge/`, `lib/mdns/`, `lib/cert/`, `lib/router/`, and
`lib/ip-history.nix` all generate their actual Python via multiple
`.nix` files, each returning one complete, self-contained function
definition as a string, concatenated together at build time (see any
of those directories' own `default.nix`). Two things this
deliberately isn't:

- **Not one giant script per feature.** Each fragment stays under this
  repo's own ~200-300 line-per-file convention, split by concern (e.g.
  `ipv6-bridge/tls.nix`, `http-request.nix`, `http-response.nix`,
  `relay.nix`, `handler.nix`, `server.nix` -- six focused pieces
  instead of one ~250-line function).
- **Not a standalone software project either** (no `pyproject.toml`,
  no separately-versioned package). This repo already has a precedent
  for "real multi-file project, Nix-packaged" -- `Dotfiles/Quickshell/
  MyBar/`'s C++ backends, built via `backend.nix` wrapping `stdenv.
  mkDerivation` around a standalone `scripts/build/compile.sh`. That
  pattern was considered and explicitly rejected here: the actual ask
  was modularity matching `mountpoints`/the self-hosted services (`lib/
  *.nix` files, still pure Nix), not a second packaging mechanism.

Fragment order doesn't matter for correctness -- Python resolves
function calls at call time, not definition time, so as long as
everything is defined before the driving `if __name__ == "__main__":`
block runs (always the last fragment), concatenation order is free to
follow whatever's most readable (bottom-up: helpers first, the actual
`main()` last).

## One `port-forwarding` CLI, not two

`lib/cert/` and `lib/ip-history.nix` were originally two separate
PATH-installed binaries (`port-forwarding-cert`, `port-forwarding-ip-
history`). Unified into one `port-forwarding cert|history ...` command
-- a thin shell dispatcher in `port-forwarding.nix` onto each
subsystem's own already-built script, not a merge of the underlying
Python (which would risk namespace collisions between two otherwise-
independent programs for no real benefit). The systemd *unit* names
stay separate (`port-forwarding-cert-ensure.service`, `port-forwarding-
ip-history.service`/`.timer`) -- the unification is purely at the
manual-CLI layer, matching pmg's own single-binary-many-subcommands
shape (`pmg cert ...`, `pmg show ...`).

The CLI is installed unconditionally, regardless of whether any entry
currently needs auto-cert or has `ipHistory.enable = true` -- both
subcommands are genuinely useful as on-demand manual tools even when
nothing automatic depends on them yet (e.g. `port-forwarding cert
ensure` to pre-generate a cert before declaring the first entry that
needs one).

## The self-signed leaf key is `0644`, not pmg's own `0600`

pmg runs everything as root with no process isolation at all, so a
`0600` key file was never actually protecting it from anything.
Here, the ipv6-bridge services that need to *read* that key run as
`DynamicUser` -- a different, unprivileged, non-root user each
generation, with no stable group this directory could sensibly be
scoped to. `0644` (world-readable) on the leaf cert/key specifically
is what actually lets those services function; the CA's own key stays
`0600` (root-only), since compromising *that* would let an attacker
forge trusted certs for anything, a meaningfully bigger blast radius
than one service's own leaf key. Same reasoning sets `StateDirectoryMode
= "0755"` on the certs directory itself -- 0750 would block an
arbitrary `DynamicUser` from even traversing in.

This is deliberately a lower security bar than a real production TLS
key would get -- appropriate here because the whole point of this cert
is avoiding a browser warning on your own LAN, not protecting anything
a real attacker would meaningfully gain from.

## DNAT uses `networking.nat.forwardPorts`, not hand-rolled nftables

pmg prefers nftables with an iptables fallback, hand-writing the rules
either way. Checked this machine's actual state before choosing:
`networking.nftables.enable` is `false` here (the legacy iptables-nft
backend is what's actually active), and NixOS has a real, native
option for exactly pmg's DNAT use case --
`networking.nat.forwardPorts = [{ sourcePort; destination =
"127.0.0.1:<port>"; proto = "tcp"; }]` -- confirmed by reading `nixos/
modules/services/networking/nat.nix` directly, including that
`internalInterfaces`/`internalIPs` (the actual NAT-a-whole-subnet
case) are optional and unneeded for this narrower "forward to a
loopback service on the same host" case. The one thing that module
doesn't set is `net.ipv4.conf.all.route_localnet` (it only sets the
`*.forwarding` sysctls) -- `lib/dnat.nix` adds only that one sysctl on
top, nothing else hand-rolled.

## `loopbackOnly` is declared, not detected

pmg inspects a real running process's actual bind address at runtime
to decide whether DNAT is needed. There's no eval-time equivalent (see
`architecture.md`'s "pure-eval constraint" section), so this is an
explicit per-entry boolean instead -- you already know whether your
own service binds `127.0.0.1` or `0.0.0.0`, so declaring it is both
simpler and more "declarative-in-spirit" than adding another runtime
probe.

## Tor's `relay.onionServices` really doesn't need `relay.enable`

This looked like it might force becoming a public Tor relay/exit
node (a much bigger, more consequential decision than "host one hidden
service") purely from the option's naming/nesting. Verified rather
than assumed: read `nixos/modules/services/security/tor.nix` directly,
found the module's own warning text explicitly treats hidden services
on a public relay as an edge case to warn about, not a requirement,
and confirmed no `assertions` entry anywhere ties `relay.onionServices`
to `relay.enable`. Only `services.tor.enable = true` at the top level
is actually required.

## Avahi was genuinely the wrong tool, not just an inconvenient one

Considered `services.avahi.extraServiceFiles` first, since it's the
obviously-native option. Rejected after reading `avahi-daemon.nix`'s
own source: Avahi publishes one machine-wide `hostName` plus
service-*discovery* records (the `_http._tcp`-style entries Bonjour/
`dns-sd` browse) -- neither capability lets an arbitrary custom name
like `pmg-8096.local` resolve directly when typed into a browser's URL
bar, which is specifically what pmg's own hand-rolled `mdns_responder.
py` does (answers raw A/AAAA queries for whatever name you give it).
These are different DNS-record-level capabilities, not a style
difference -- reimplementing pmg's own responder was the only way to
actually match its behavior.
