// &desc: "Host-side NAT for sandbox networking: one nftables table holding an outbound MASQUERADE chain (if `Config::outbound`) and/or an inbound DNAT chain pair (one PREROUTING rule + one identical OUTPUT rule per `Config::inbound` port -- see `CHAIN_IN_OUTPUT`'s doc comment for why both hooks are required) plus one narrow hairpin-MASQUERADE rule in postrouting (see `new_hairpin_masquerade_rule_msg`'s doc comment for why loopback-sourced forwarded traffic specifically needs this on top of the DNAT rules), all built from raw NETLINK_NETFILTER messages (linux/netfilter/nfnetlink.h, linux/netfilter/nf_tables.h) -- no nft(8) shell-out, no nftables crate. Outbound is scoped to traffic leaving via the sandbox's own veth end (`iifname casnet0`) only; inbound DNAT rules match on destination port only (by design -- a forwarded port is meant to be reachable from wherever can reach this host, not just casnet0). Neither ever touches any other rule/table on the host."
use std::io;

use super::super::netlink::{self, MsgBuilder};
use super::{Config, PortForward, SANDBOX_IP};

// --- NETLINK_NETFILTER / nftables wire format -- linux/netfilter/
// nfnetlink.h (subsystem framing) and linux/netfilter/nf_tables.h
// (message types, attribute numbers, expression encodings). Same
// fixed-kernel-ABI category as this module's rtnetlink sibling.
const NFNL_SUBSYS_NFTABLES: u16 = 10;
const NLM_F_APPEND: u16 = 0x0800;

const NFT_MSG_NEWTABLE: u16 = 0;
const NFT_MSG_DELTABLE: u16 = 2;
const NFT_MSG_NEWCHAIN: u16 = 3;
const NFT_MSG_NEWRULE: u16 = 6;

fn msg_type(nft_msg: u16) -> u16 {
    (NFNL_SUBSYS_NFTABLES << 8) | nft_msg
}

const NFTA_TABLE_NAME: u16 = 1;

const NFTA_CHAIN_TABLE: u16 = 1;
const NFTA_CHAIN_NAME: u16 = 3;
const NFTA_CHAIN_HOOK: u16 = 4;
const NFTA_CHAIN_TYPE: u16 = 7;

const NFTA_HOOK_HOOKNUM: u16 = 1;
const NFTA_HOOK_PRIORITY: u16 = 2;
const NF_INET_PRE_ROUTING: u32 = 0;
const NF_INET_LOCAL_OUT: u32 = 3;
const NF_INET_POST_ROUTING: u32 = 4;
const NF_IP_PRI_NAT_DST: i32 = -100;
const NF_IP_PRI_NAT_SRC: i32 = 100;

const NFTA_RULE_TABLE: u16 = 1;
const NFTA_RULE_CHAIN: u16 = 2;
const NFTA_RULE_EXPRESSIONS: u16 = 4;

const NFTA_LIST_ELEM: u16 = 1;
const NFTA_EXPR_NAME: u16 = 1;
const NFTA_EXPR_DATA: u16 = 2;

const NFTA_META_DREG: u16 = 1;
const NFTA_META_KEY: u16 = 2;
const NFT_META_IIFNAME: u32 = 6;
const NFT_META_L4PROTO: u32 = 16;

const NFTA_PAYLOAD_DREG: u16 = 1;
const NFTA_PAYLOAD_BASE: u16 = 2;
const NFTA_PAYLOAD_OFFSET: u16 = 3;
const NFTA_PAYLOAD_LEN: u16 = 4;
const NFT_PAYLOAD_NETWORK_HEADER: u32 = 1;
const NFT_PAYLOAD_TRANSPORT_HEADER: u32 = 2;

const NFTA_CMP_SREG: u16 = 1;
const NFTA_CMP_OP: u16 = 2;
const NFTA_CMP_DATA: u16 = 3;
const NFT_CMP_EQ: u32 = 0;
const NFTA_DATA_VALUE: u16 = 1;

const NFTA_IMMEDIATE_DREG: u16 = 1;
const NFTA_IMMEDIATE_DATA: u16 = 2;

const NFTA_NAT_TYPE: u16 = 1;
const NFTA_NAT_FAMILY: u16 = 2;
const NFTA_NAT_REG_ADDR_MIN: u16 = 3;
const NFTA_NAT_REG_PROTO_MIN: u16 = 5;
const NFT_NAT_DNAT: u32 = 1;

const NFT_REG_1: u32 = 1;
const NFT_REG_2: u32 = 2;

const TABLE_NAME: &str = "cas_sandbox";
const CHAIN_OUT: &str = "postrouting";
const CHAIN_IN: &str = "prerouting";
/// A second copy of the DNAT rule, hooked at `NF_INET_LOCAL_OUT` instead
/// of `NF_INET_PRE_ROUTING` -- see this module's doc comment on why
/// `PREROUTING` alone silently does nothing for traffic *originated by
/// the host itself* (the exact case the bug report's own repro used,
/// connecting from a shell on the same machine running `cas`). Named
/// distinctly from `CHAIN_IN` even though it carries the identical rule
/// content, matching the real `nft`/Docker convention of two separate
/// chains (one per hook) rather than one chain attached to two hooks
/// (nftables base chains are always exactly one hook each).
const CHAIN_IN_OUTPUT: &str = "output";
const IFACE_HOST: &str = super::IFACE_HOST;

#[repr(C)]
struct NfGenMsg {
    family: u8,
    version: u8,
    res_id: u16, // big-endian on the wire, but 0 either way -- no byteswap needed
}

fn as_bytes<T>(v: &T) -> &[u8] {
    unsafe { std::slice::from_raw_parts(v as *const T as *const u8, std::mem::size_of::<T>()) }
}

fn nfgen(family: u8) -> NfGenMsg {
    NfGenMsg { family, version: 0, res_id: 0 }
}

/// Builds and commits every table/chain/rule `cfg` calls for, in one
/// nftables batch (`netlink::nft_batch`) -- table/chain/rule creation
/// order matters (a chain needs its table, a rule needs its chain), and
/// nftables netlink rejects a bare individual `NEWTABLE`/`NEWCHAIN`/
/// `NEWRULE` outside a `BATCH_BEGIN`/`BATCH_END` transaction with
/// `EINVAL` (confirmed by straceing the real `nft` binary against this
/// exact operation), unlike rtnetlink's per-message request/ack model.
/// `cfg.outbound`/`cfg.inbound` are independent -- either, both, or (via
/// `Config::is_empty`, checked by the caller before this is ever called)
/// neither chain gets built.
pub fn apply(cfg: &Config) -> io::Result<()> {
    let fd = netlink::open(netlink::NETLINK_NETFILTER)?;
    let mut messages = vec![new_table_msg(1)];
    let mut seq = 2;
    // The postrouting chain is shared by two independent rules below --
    // `cfg.outbound`'s own MASQUERADE (scoped to `iifname casnet0`, the
    // sandbox's own outbound traffic) and `cfg.inbound`'s hairpin
    // MASQUERADE (see `new_hairpin_masquerade_rule_msg`'s doc comment) --
    // so it needs to exist whenever *either* is requested, not only
    // `cfg.outbound`.
    if cfg.outbound || !cfg.inbound.is_empty() {
        messages.push(new_postrouting_chain_msg(seq));
        seq += 1;
    }
    if cfg.outbound {
        messages.push(new_masquerade_rule_msg(seq));
        seq += 1;
    }
    if !cfg.inbound.is_empty() {
        messages.push(new_prerouting_chain_msg(seq));
        seq += 1;
        messages.push(new_local_out_chain_msg(seq));
        seq += 1;
        // One hairpin MASQUERADE rule total, not one per forwarded port --
        // it matches on source/destination address only (see its own doc
        // comment), which is identical for every `PortForward` in
        // `cfg.inbound` (`SANDBOX_IP` never varies).
        messages.push(new_hairpin_masquerade_rule_msg(seq));
        seq += 1;
        for pf in &cfg.inbound {
            // Both copies are required -- see `CHAIN_IN_OUTPUT`'s doc
            // comment. `PREROUTING` alone only ever matches traffic that
            // arrives already destined elsewhere and gets forwarded
            // in/through this host (i.e. genuinely remote clients);
            // anything the host itself originates -- including a test
            // `nc`/`curl` run in a second shell on the very machine
            // running `cas`, which is exactly how this bug was both
            // found and is verified fixed -- is routed to `lo` internally
            // by the kernel before any hook table decision, bypassing
            // `PREROUTING` entirely and only ever traversing `OUTPUT`/
            // `POSTROUTING`. This isn't limited to `127.0.0.1`: *any*
            // locally-originated packet whose destination is one of the
            // host's own addresses (e.g. the real interface IP used in
            // the bug report's repro, `10.0.2.15`) takes the same
            // `RTN_LOCAL` path and skips `PREROUTING` the same way --
            // the bug report's own reasoning that testing a non-loopback
            // local address "ruled out" the well-known loopback quirk
            // was the actual mistake, since that quirk isn't really
            // loopback-specific, it's "local-origin"-specific. `nft`'s
            // own documented workaround (and Docker's, referenced in the
            // bug report) is precisely a second identical rule on
            // `OUTPUT` for this reason.
            messages.push(new_dnat_rule_msg(seq, pf, CHAIN_IN));
            seq += 1;
            messages.push(new_dnat_rule_msg(seq, pf, CHAIN_IN_OUTPUT));
            seq += 1;
        }
    }
    let r = netlink::nft_batch(fd, NFNL_SUBSYS_NFTABLES, messages, 1);
    netlink::close(fd);
    r
}

pub fn delete_all() -> io::Result<()> {
    let fd = netlink::open(netlink::NETLINK_NETFILTER)?;
    // Deleting the table deletes every chain/rule inside it too -- no
    // need to delete anything individually first.
    let r = netlink::nft_batch(fd, NFNL_SUBSYS_NFTABLES, vec![del_table_msg(1)], 1);
    netlink::close(fd);
    r
}

fn new_table_msg(seq: u32) -> Vec<u8> {
    let gen = nfgen(libc::AF_INET as u8);
    let mut b = MsgBuilder::new(msg_type(NFT_MSG_NEWTABLE), 0, as_bytes(&gen));
    b.push_attr_str(NFTA_TABLE_NAME, TABLE_NAME);
    b.finish_raw(msg_type(NFT_MSG_NEWTABLE), 0, seq)
}

fn del_table_msg(seq: u32) -> Vec<u8> {
    let gen = nfgen(libc::AF_INET as u8);
    let mut b = MsgBuilder::new(msg_type(NFT_MSG_DELTABLE), 0, as_bytes(&gen));
    b.push_attr_str(NFTA_TABLE_NAME, TABLE_NAME);
    b.finish_raw(msg_type(NFT_MSG_DELTABLE), 0, seq)
}

fn new_base_chain_msg(seq: u32, name: &str, hooknum: u32, priority: i32) -> Vec<u8> {
    let gen = nfgen(libc::AF_INET as u8);
    let mut b = MsgBuilder::new(msg_type(NFT_MSG_NEWCHAIN), 0, as_bytes(&gen));
    b.push_attr_str(NFTA_CHAIN_TABLE, TABLE_NAME);
    b.push_attr_str(NFTA_CHAIN_NAME, name);
    b.push_attr_str(NFTA_CHAIN_TYPE, "nat");
    b.nest_start(NFTA_CHAIN_HOOK);
    // Both fields are `__be32`/`__be32`(as a signed priority) on the wire
    // -- explicit big-endian, not `push_attr_u32` (native/little-endian
    // on x86_64), confirmed by diffing against the real `nft` binary's
    // own encoding of the same "hook ... priority ..." via strace.
    b.push_attr(NFTA_HOOK_HOOKNUM, &hooknum.to_be_bytes());
    b.push_attr(NFTA_HOOK_PRIORITY, &priority.to_be_bytes());
    b.nest_end();
    b.finish_raw(msg_type(NFT_MSG_NEWCHAIN), netlink::NLM_F_CREATE, seq)
}

fn new_postrouting_chain_msg(seq: u32) -> Vec<u8> {
    new_base_chain_msg(seq, CHAIN_OUT, NF_INET_POST_ROUTING, NF_IP_PRI_NAT_SRC)
}

fn new_prerouting_chain_msg(seq: u32) -> Vec<u8> {
    new_base_chain_msg(seq, CHAIN_IN, NF_INET_PRE_ROUTING, NF_IP_PRI_NAT_DST)
}

/// See `CHAIN_IN_OUTPUT`'s doc comment -- same "nat"/DNAT chain type and
/// priority as `new_prerouting_chain_msg`, just hooked at
/// `NF_INET_LOCAL_OUT` instead of `NF_INET_PRE_ROUTING` so
/// locally-originated packets get the same destination-address rewrite.
/// The kernel re-runs the routing decision for `OUTPUT`-hook DNAT
/// automatically (`ip_route_me_harder`, standard netfilter core
/// behavior for this exact hook) -- no extra route/rule needed here for
/// the rewritten packet to actually reach `casnet0`.
fn new_local_out_chain_msg(seq: u32) -> Vec<u8> {
    new_base_chain_msg(seq, CHAIN_IN_OUTPUT, NF_INET_LOCAL_OUT, NF_IP_PRI_NAT_DST)
}

fn new_masquerade_rule_msg(seq: u32) -> Vec<u8> {
    let gen = nfgen(libc::AF_INET as u8);
    let mut b = MsgBuilder::new(msg_type(NFT_MSG_NEWRULE), 0, as_bytes(&gen));
    b.push_attr_str(NFTA_RULE_TABLE, TABLE_NAME);
    b.push_attr_str(NFTA_RULE_CHAIN, CHAIN_OUT);
    b.nest_start(NFTA_RULE_EXPRESSIONS);

    // expr 1/2: "iifname casnet0" -- load the packet's ingress interface
    // name into NFT_REG_1, compare against our host-side veth name.
    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "meta");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_META_DREG, NFT_REG_1);
    b.push_attr_u32_be(NFTA_META_KEY, NFT_META_IIFNAME);
    b.nest_end();
    b.nest_end();

    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "cmp");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_CMP_SREG, NFT_REG_1);
    b.push_attr_u32_be(NFTA_CMP_OP, NFT_CMP_EQ);
    // Interface-name compare data is always the full IFNAMSIZ (16 bytes,
    // NUL-padded) on the wire, not just the string's own length+NUL --
    // confirmed against real `nft`'s encoding of the same `iifname "..."`
    // match; a short buffer here is exactly the kind of thing that
    // parses fine but never actually matches at runtime.
    let mut ifname = [0u8; 16];
    let name_bytes = IFACE_HOST.as_bytes();
    ifname[..name_bytes.len()].copy_from_slice(name_bytes);
    b.nest_start(NFTA_CMP_DATA);
    b.push_attr(NFTA_DATA_VALUE, &ifname);
    b.nest_end();
    b.nest_end();
    b.nest_end();

    // expr 3: "masquerade" -- no flags/port range, the plain form.
    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "masq");
    b.nest_end();

    b.nest_end(); // NFTA_RULE_EXPRESSIONS
    b.finish_raw(msg_type(NFT_MSG_NEWRULE), netlink::NLM_F_CREATE | NLM_F_APPEND, seq)
}

/// `ip saddr 127.0.0.0/8 ip daddr <SANDBOX_IP> masquerade` -- rewrites
/// the *source* of forwarded traffic to the host's own veth address
/// (`HOST_IP`) when (and only when) that traffic originated from the
/// host's own loopback range, on top of the `PREROUTING`/`OUTPUT` DNAT
/// rules that rewrite its *destination*. Both DNAT copies existing is
/// necessary but not sufficient for the `127.0.0.1` case in the bug
/// report's repro -- confirmed by isolating each piece manually outside
/// `cas` entirely (raw `ip netns`/`nft`/`arping`, not this module) after
/// `enable_loopback_hairpin`'s two sysctls alone (in `network.rs`) turned
/// out to only fix ARP resolution, not the actual TCP handshake:
///
/// - With only the DNAT rules and `route_localnet`/`accept_local`, the
///   host successfully ARPs the sandbox's veth address and the DNAT'd SYN
///   packet visibly arrives on `casnet0p` (confirmed via `tcpdump` run
///   *inside* the sandbox's own netns) -- but the sandbox's TCP stack
///   never replies, and no counter (`InDiscards`, martian-source logging
///   via `log_martians`) records why. This is the standard "hairpin NAT"
///   problem: the sandbox's socket layer accepts the packet, but its
///   *reply* would need a route back to `127.0.0.1`, an address that
///   means something different (or nothing at all reachable via this
///   veth) inside the sandbox's own separate netns than it did for the
///   host process that opened the connection -- there is no real
///   TCP-layer response possible without also disguising the source.
/// - Manually adding just this MASQUERADE rule (no DNAT changes) does
///   *not* fix it either -- the DNAT'd destination still needs
///   `route_localnet`/`accept_local` to be acceptable to the sandbox at
///   all before source rewriting is even relevant.
/// - Both together, and *only* both together, made a bare `nc -z
///   127.0.0.1 <port>` succeed against a hand-built veth+nftables setup
///   completely outside `cas` -- the same experiment that ruled out every
///   other hypothesis first.
///
/// Scoped narrowly to `saddr 127.0.0.0/8` (not e.g. a blanket "masquerade
/// anything destined for `SANDBOX_IP`") deliberately: a genuinely remote
/// or LAN client connecting to a forwarded port should still see its own
/// real source address preserved inside the sandbox, matching this
/// module's `NFTA_RULE_EXPRESSIONS`-per-workload precision philosophy --
/// confirmed this narrower match still lets a non-loopback source (e.g.
/// the bug report's `10.0.2.15` case) connect successfully without being
/// masqueraded away.
fn new_hairpin_masquerade_rule_msg(seq: u32) -> Vec<u8> {
    let gen = nfgen(libc::AF_INET as u8);
    let mut b = MsgBuilder::new(msg_type(NFT_MSG_NEWRULE), 0, as_bytes(&gen));
    b.push_attr_str(NFTA_RULE_TABLE, TABLE_NAME);
    b.push_attr_str(NFTA_RULE_CHAIN, CHAIN_OUT);
    b.nest_start(NFTA_RULE_EXPRESSIONS);

    // expr 1/2: "ip saddr 127.0.0.0/8" -- only the first octet needs
    // comparing (127.0.0.0/8 is exactly "first byte == 127"), so this
    // loads 1 byte at network-header offset 0 (source address starts
    // right after the 12-byte IPv4 header's version/ihl/tos/len/id/
    // flags/frag/ttl/proto/checksum fields) rather than a 4-byte load +
    // a separate mask/and expression for the /8 -- simpler and exactly
    // equivalent for this specific prefix length.
    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "payload");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_PAYLOAD_DREG, NFT_REG_1);
    b.push_attr_u32_be(NFTA_PAYLOAD_BASE, NFT_PAYLOAD_NETWORK_HEADER);
    b.push_attr_u32_be(NFTA_PAYLOAD_OFFSET, 12);
    b.push_attr_u32_be(NFTA_PAYLOAD_LEN, 1);
    b.nest_end();
    b.nest_end();

    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "cmp");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_CMP_SREG, NFT_REG_1);
    b.push_attr_u32_be(NFTA_CMP_OP, NFT_CMP_EQ);
    b.nest_start(NFTA_CMP_DATA);
    b.push_attr(NFTA_DATA_VALUE, &[127u8]);
    b.nest_end();
    b.nest_end();
    b.nest_end();

    // expr 3/4: "ip daddr <SANDBOX_IP>" -- the full 4-byte destination
    // address, at network-header offset 16 (straight after the 4-byte
    // source address this rule just matched at offset 12).
    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "payload");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_PAYLOAD_DREG, NFT_REG_1);
    b.push_attr_u32_be(NFTA_PAYLOAD_BASE, NFT_PAYLOAD_NETWORK_HEADER);
    b.push_attr_u32_be(NFTA_PAYLOAD_OFFSET, 16);
    b.push_attr_u32_be(NFTA_PAYLOAD_LEN, 4);
    b.nest_end();
    b.nest_end();

    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "cmp");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_CMP_SREG, NFT_REG_1);
    b.push_attr_u32_be(NFTA_CMP_OP, NFT_CMP_EQ);
    b.nest_start(NFTA_CMP_DATA);
    b.push_attr(NFTA_DATA_VALUE, &SANDBOX_IP);
    b.nest_end();
    b.nest_end();
    b.nest_end();

    // expr 5: "masquerade" -- same plain form as the outbound rule.
    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "masq");
    b.nest_end();

    b.nest_end(); // NFTA_RULE_EXPRESSIONS
    b.finish_raw(msg_type(NFT_MSG_NEWRULE), netlink::NLM_F_CREATE | NLM_F_APPEND, seq)
}

/// One rule: `<protocol> dport <host_port> dnat to <SANDBOX_IP>:<sandbox_port>`.
/// No interface restriction (unlike the masquerade rule) -- a forwarded
/// port is meant to be reachable from wherever can reach this host at
/// all (LAN, the internet, depending on the host's own exposure), not
/// just from the sandbox's own veth. `chain` is which base chain to
/// attach this copy to -- `apply` calls this once per chain (`CHAIN_IN`
/// and `CHAIN_IN_OUTPUT`) with otherwise-identical content; see
/// `CHAIN_IN_OUTPUT`'s doc comment for why one rule needs to exist in
/// both.
fn new_dnat_rule_msg(seq: u32, pf: &PortForward, chain: &str) -> Vec<u8> {
    let gen = nfgen(libc::AF_INET as u8);
    let mut b = MsgBuilder::new(msg_type(NFT_MSG_NEWRULE), 0, as_bytes(&gen));
    b.push_attr_str(NFTA_RULE_TABLE, TABLE_NAME);
    b.push_attr_str(NFTA_RULE_CHAIN, chain);
    b.nest_start(NFTA_RULE_EXPRESSIONS);

    // expr 1/2: match the transport protocol (tcp=6, udp=17) via
    // `meta l4proto`.
    let l4proto: u8 = if pf.tcp { 6 } else { 17 };
    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "meta");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_META_DREG, NFT_REG_1);
    b.push_attr_u32_be(NFTA_META_KEY, NFT_META_L4PROTO);
    b.nest_end();
    b.nest_end();

    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "cmp");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_CMP_SREG, NFT_REG_1);
    b.push_attr_u32_be(NFTA_CMP_OP, NFT_CMP_EQ);
    b.nest_start(NFTA_CMP_DATA);
    b.push_attr(NFTA_DATA_VALUE, &[l4proto]);
    b.nest_end();
    b.nest_end();
    b.nest_end();

    // expr 3/4: match the destination port -- 2 bytes at offset 2 into
    // the transport header (same position for both tcp and udp dport).
    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "payload");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_PAYLOAD_DREG, NFT_REG_1);
    b.push_attr_u32_be(NFTA_PAYLOAD_BASE, NFT_PAYLOAD_TRANSPORT_HEADER);
    b.push_attr_u32_be(NFTA_PAYLOAD_OFFSET, 2);
    b.push_attr_u32_be(NFTA_PAYLOAD_LEN, 2);
    b.nest_end();
    b.nest_end();

    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "cmp");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_CMP_SREG, NFT_REG_1);
    b.push_attr_u32_be(NFTA_CMP_OP, NFT_CMP_EQ);
    b.nest_start(NFTA_CMP_DATA);
    b.push_attr(NFTA_DATA_VALUE, &pf.host_port.to_be_bytes());
    b.nest_end();
    b.nest_end();
    b.nest_end();

    // expr 5/6: load the DNAT target address/port into registers via
    // "immediate", then expr 7 references both in a single "nat"
    // (type=DNAT) statement.
    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "immediate");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_IMMEDIATE_DREG, NFT_REG_1);
    b.nest_start(NFTA_IMMEDIATE_DATA);
    b.push_attr(NFTA_DATA_VALUE, &SANDBOX_IP);
    b.nest_end();
    b.nest_end();
    b.nest_end();

    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "immediate");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_IMMEDIATE_DREG, NFT_REG_2);
    b.nest_start(NFTA_IMMEDIATE_DATA);
    b.push_attr(NFTA_DATA_VALUE, &pf.sandbox_port.to_be_bytes());
    b.nest_end();
    b.nest_end();
    b.nest_end();

    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "nat");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_NAT_TYPE, NFT_NAT_DNAT);
    b.push_attr_u32_be(NFTA_NAT_FAMILY, libc::AF_INET as u32);
    b.push_attr_u32_be(NFTA_NAT_REG_ADDR_MIN, NFT_REG_1);
    b.push_attr_u32_be(NFTA_NAT_REG_PROTO_MIN, NFT_REG_2);
    b.nest_end();
    b.nest_end();

    b.nest_end(); // NFTA_RULE_EXPRESSIONS
    b.finish_raw(msg_type(NFT_MSG_NEWRULE), netlink::NLM_F_CREATE | NLM_F_APPEND, seq)
}
