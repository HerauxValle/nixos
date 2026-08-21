<!-- &desc: "Bug: settings security sandbox network inbound add/enable reports success and exec prints 'network: inbound forwarding active', but no DNAT actually happens -- a connection to the forwarded port on the host's loopback address, real interface address, or any host-reachable address never reaches the listener inside the sandbox. Only connecting directly to the sandbox's own veth peer IP works, which has nothing to do with the inbound-forwarding feature (it's just routing since ip_forward is on)." -->
# `sandbox network inbound` doesn't actually forward anything

## Severity: functional (not itself an exposure -- fails closed, not open) but the security feature silently does nothing

## Repro (audit VM, current source as of 1.17.0 session)
```
cas rfs settings security sandbox namespaces enable net --pass "..."
cas rfs settings security sandbox network inbound add 9999 --pass "..."
cas rfs settings security sandbox network inbound enable --pass "..."
cas rfs exec --rootfs dev --pass "..." -- /bin/busybox nc -lp 9999 -e /bin/busybox echo hello-from-sandbox &
#   [i] network: inbound forwarding active (9999->9999)

# from the HOST, in a separate shell, while the above is still running:
nc 127.0.0.1 9999        # -> connection fails, no response
nc 10.0.2.15 9999        # -> the VM's real, non-loopback interface address -- also fails
nc 10.200.99.2 9999      # -> the sandbox's own veth peer address -- SUCCEEDS, prints "hello-from-sandbox"
```
Tested against both the host's loopback address AND its real external
interface address (`10.0.2.15`, confirmed via `ip -4 addr show`) to
rule out the well-known Linux quirk where locally-originated loopback
traffic skips the `PREROUTING` chain (the reason e.g. Docker needs a
matching `OUTPUT`-chain rule for `-p` to work via `127.0.0.1`) --
neither address works, which rules that out as the explanation. Only
reaching the sandbox's own veth address directly succeeds, and that
works purely because `/proc/sys/net/ipv4/ip_forward` is turned on by
the outbound/inbound session setup (confirmed in `network.rs`) — it's
ordinary IP forwarding/routing, nothing to do with the inbound-forward
feature's DNAT rule actually existing.

## Root cause (not yet located precisely -- needs source investigation)
`src/sandbox/network.rs`'s own doc comment says the veth+NAT setup
(including inbound DNAT) is built from raw rtnetlink/netfilter-netlink
messages via `netlink.rs`, with no `iptables(8)`/`nft(8)` shell-out.
The outbound MASQUERADE path is confirmed working (tested separately,
`wget` through it got a real response from `1.1.1.1`). The inbound DNAT
rule construction is presumably in the same file or `netlink.rs`, but
wasn't located by grep for obvious keywords (`chain`, `dnat`, `DNAT`,
`PREROUTING`) — the actual nftables rule-building code likely uses raw
hook numbers or lower-level netlink attribute constants rather than
those literal strings. A fixer needs to read the actual rule
construction (probably a function building an `NFT_MSG_NEWRULE` with a
`dnat` expression) and compare against a known-working manual
`nft`/`iptables` DNAT rule to find what's missing or wrong -- candidate
hypotheses, none confirmed:
- The rule is added to the wrong chain/hook (e.g. only `FORWARD`, never
  `PREROUTING`), so packets destined for the host's own address never
  hit it before the kernel decides "not for me" isn't even reached
  correctly for redirect purposes.
- The rule's match conditions (destination port, protocol, interface)
  don't actually match real incoming host traffic.
- The DNAT target address/port encoding in the raw netlink message is
  wrong (a manually hand-rolled netlink `dnat` expression is a very
  easy place for a byte-order or attribute-nesting mistake to silently
  produce a rule that "exists" per `enable`'s own success message and
  any local ruleset dump, but never actually matches traffic).
- The rule is created in the wrong netfilter table/family (`ip` vs
  `inet` vs a table only visible from a network namespace other than
  the host's init namespace).

## Blast radius
Not an exposure -- the feature currently does *less* than advertised,
not more, so nothing is more open than the user configured. But it's a
real, confirmed functional bug in a documented security-relevant
feature: a user who enables `sandbox network inbound` to expose a
service running inside the sandbox (e.g. testing a web server) will
find it simply doesn't work, with the tool's own status output
actively claiming otherwise ("network: inbound forwarding active").
That's a trust problem for a security tool specifically -- if this
silently-broken pattern extends to something the user is depending on
for isolation rather than connectivity, that would be far more
serious; this specific instance happens to fail safe.

## Suggested fix direction
Read `src/sandbox/network.rs` and `src/sandbox/netlink.rs` fully,
paying particular attention to whatever function builds the inbound
port-forward's nftables rule (likely near the outbound MASQUERADE
construction, given the doc comment groups them as "both rely on...").
Compare its raw netlink message construction against a byte-for-byte
correct example (e.g. capture the netlink traffic from a known-working
manual `nft add rule ... dnat to :PORT` using `nft --debug=netlink` or
`strace` on the `nft` binary, and diff it against what cas emits) to
find the actual encoding bug, rather than guessing. Add an integration
check that doesn't just assert the CLI reports success, but performs
an actual host-to-sandbox connection through the forwarded port and
verifies real data flows, since this bug demonstrates that the
CLI's own success/status messages are not a reliable signal for
whether the underlying netlink rule construction actually worked.
