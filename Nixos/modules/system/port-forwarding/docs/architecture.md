# How it fits together

## The entry schema

`config.vars.system.ports.entries` is `attrsOf (submodule ...)`, not the
looser `listOf attrs` this repo uses for simpler things like
`vars.scripts` (see `packages/scripts/default.nix`). Two reasons:

1. Fields interact -- `tls.certFile`/`tls.keyFile` must be set
   together (an `assertions` entry in `port-forwarding.nix` enforces
   this; see "assertions live at the top level" below for why that
   isn't inside the submodule itself). `onion`/`local`/`public`/
   `router` used to interact too (mutually exclusive, mirroring pmg's
   own CLI flags), but that constraint was dropped entirely -- each is
   a fully independent mechanism, confirmed by reading every one of
   them directly, so any combination can be true on the same entry.
2. The attrset key doubles as the addressable name -- `config.vars.
   ports.entries.jellyfin` -- and every `key`/`entry` pair downstream
   (bridge, mdns, tunnel) is threaded through by that same key, so
   systemd unit names, log prefixes, and generated script filenames
   all agree without a separate "name" field to keep in sync.

Fields are grouped by concern, not one flat list -- `port`/`enabled`/
`service`/`blocking` stay top-level (facts about the entry as a
whole), `net.*` is layer-3/4 reachability (`ipv4`/`ipv6`/
`loopbackOnly`), `tls.*` is how the IPv6 bridge handles TLS
(`mode`/`certFile`/`keyFile`), `mode.*` is which exposure mechanism(s)
are active (`onion`/`local`/`public`/`router`). Two of those four
fields are themselves `false` | `true` | `{ ... }` via
`lib.types.coercedTo` (the same NixOS-idiomatic bool-or-submodule
shape `services.tor`'s own `HiddenServicePort.map` option uses) rather
than plain booleans: `mode.local` accepts `{ name = "custom"; }`
(replacing the old separate `localName` field), and `mode.onion`
accepts `{ ephemeral = true; }` (a fresh v3 address every
`tor.service` start instead of the default persistent one -- see
`decisions.md`'s own section on this).

## One flat attrset, not a top-level `lib.mkMerge` list

`port-forwarding.nix`'s final return value is a single attrset with
static top-level keys (`networking`, `services`, `systemd`, `system`,
`environment`), never `lib.mkMerge [ ... per-entry mkMerge/
mapAttrsToList calls ... ]` as the *whole module's* result.

This isn't a style preference -- it was a real infinite-recursion bug,
confirmed live. NixOS has to evaluate every module's `config` to
determine all contributions to `config.vars.system.ports.entries` (checking
for unmatched/free-form definitions). A `lib.mkMerge` whose *list
itself* is built by `lib.mapAttrsToList f entries` can't reveal its
own length or contents without forcing `entries` first -- which is
exactly the value being resolved. The fix: keep the top-level
attrset's keys statically visible (a plain `{ systemd.services = ...;
}` literal), and only use `lib.mkIf`/`lib.mkMerge` for the *values*
under an already-known key, never as a list element whose presence
depends on `entries`.

The same root cause bit a second time inside `system.activationScripts.
port-forwarding-upnp.text`: that option is `types.lines` with no
default, so `lib.mkIf false "..."` doesn't contribute an empty string
the way you'd expect -- it drops the definition entirely, and with
nothing else defining that key, evaluation fails outright the moment
the condition is ever false. `lib.optionalString` (always yields a
real string, empty or not) is the fix, documented independently in
`modules/services/self-hosted/dotfiles.nix` after the same trap there.

## Lifecycle binding, not a reimplemented watcher

pmg's own netlink-based watcher polls for a service's listener to come
up or go down, then applies/tears down onion/local/public exposure
reactively. None of that exists here -- instead, each entry's optional
`service` field wires three things onto the generated systemd unit:

```nix
wantedBy = [ entry.service ];   # entry.service *wants* this unit
bindsTo  = [ entry.service ];   # stop when entry.service stops
after    = [ entry.service ];   # start after entry.service
```

`wantedBy` here is the interesting one: it's a *reverse* declaration.
Setting `wantedBy = [ "foo.service" ]` on unit A means "A wants to be
wanted by foo.service" -- systemd generates a `Wants=` dependency
pointing at A *from* foo.service's own unit, without foo.service's own
definition (owned by a completely different module, e.g.
`self-hosted-jellyfin.service`) ever needing to know port-forwarding
exists. This is how NixOS's `wantedBy` is designed to work generally,
just applied here specifically so a bridge/mdns/tunnel unit starts and
stops in lockstep with the real service it's exposing, with zero
polling.

`entry.service = null` (the default) skips all three and falls back to
`wantedBy = [ "multi-user.target" ]` -- always-on the moment the entry
is declared, matching the case where there's no specific unit to track
(e.g. exposing a bare TCP port nothing else in this repo manages).

## The pure-eval constraint

Confirmed live, twice, independently: `nixos-rebuild switch` (as
`pacnix rebuild` calls it) evaluates under pure-eval, where
`builtins.pathExists`/`readFile` on an arbitrary absolute host path
(not part of the flake's own tracked source) is unreliable -- it
reported a disk that was genuinely attached as "missing"
(`modules/system/mountpoints`), and would have done the same for a
UUID-presence or route-table check here. Anything that needs to
observe real, current machine state (a UUID's presence, the local
IP, a router's UPnP support) has to be a runtime bash/Python check
inside `system.activationScripts` or a systemd unit's own `ExecStart`,
never a Nix-eval-time `builtins.*` call against the live filesystem.

This is *why* `lib/upnp.nix` is an activation script rather than a
declared `networking.nat`-style option, why the IPv6 bridge/mDNS
responder/router all detect their own local IP at their own runtime
rather than baking one in from Nix, and why `lib/cert/`'s SAN list is
the one exception -- it's built entirely from `config.vars.system.ports.
entries` (already known at eval time), not from any live disk/network
state, so it's computed once in Nix and never re-derived at runtime.

## Assertions live at the top level, not inside the submodule

`config.assertions` is a real, specific NixOS mechanism (collected
across every module, checked once during `system.build.toplevel`
assembly) -- it does not auto-propagate up from an arbitrary *nested*
submodule instance the way a plain NixOS module's own `config.
assertions` does. Confirmed live: declaring `config.assertions =
[ ... ];` inside `lib/entry-type.nix`'s own submodule just creates an
unrecognized local option there ("The option `...assertions' does not
exist"), and it never reaches the real, top-level `config.assertions`
at all. The `tls.certFile`/`tls.keyFile`-pairing check lives in
`port-forwarding.nix` instead, computed by mapping over `entries`
directly, where `config.assertions` is the genuine top-level option.
(A second assertion used to live here too -- `onion`/`local`/`public`/
`router` being mutually exclusive, mirroring pmg's own CLI flags -- but
that was dropped entirely: each is a fully independent mechanism with
no real conflict, confirmed by reading every one of `lib/mdns/`,
`lib/cert/`, `lib/public-tunnel.nix`, `lib/upnp.nix`, and
`services.tor.relay.onionServices` directly. Any combination of the
four can be true on the same entry now.)
