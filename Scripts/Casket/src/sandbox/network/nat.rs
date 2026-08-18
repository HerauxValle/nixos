// &desc: "The MASQUERADE half of sandbox internet: one nftables table/chain/rule built from raw NETLINK_NETFILTER messages (linux/netfilter/nfnetlink.h, linux/netfilter/nf_tables.h) -- no nft(8) shell-out, no nftables crate. Scoped to traffic entering the host's own postrouting from the sandbox's veth end (`iifname casnet0`) only -- never touches any other rule/table on the host."
use std::io;

use super::super::netlink::{self, MsgBuilder};

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
const NF_INET_POST_ROUTING: u32 = 4;
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

const NFTA_CMP_SREG: u16 = 1;
const NFTA_CMP_OP: u16 = 2;
const NFTA_CMP_DATA: u16 = 3;
const NFT_CMP_EQ: u32 = 0;
const NFTA_DATA_VALUE: u16 = 1;

const NFT_REG_1: u32 = 1;

const TABLE_NAME: &str = "cas_sandbox";
const CHAIN_NAME: &str = "postrouting";
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

/// Table/chain/rule creation order matters (a chain needs its table to
/// exist, a rule needs its chain) -- all three are folded into one
/// nftables *batch* (`netlink::nft_batch`) and committed atomically:
/// nftables netlink rejects a bare individual `NEWTABLE`/`NEWCHAIN`/
/// `NEWRULE` outside a `BATCH_BEGIN`/`BATCH_END` transaction with
/// `EINVAL` (confirmed by straceing the real `nft` binary against this
/// exact operation), unlike rtnetlink's per-message request/ack model.
/// A failed batch commits nothing at all -- no separate rollback logic
/// needed here the way `network::setup_host_side` needs one for its
/// (non-transactional) rtnetlink calls.
pub fn add_masquerade_rule() -> io::Result<()> {
    let fd = netlink::open(netlink::NETLINK_NETFILTER)?;
    let messages = vec![new_table_msg(), new_chain_msg(), new_rule_msg()];
    let r = netlink::nft_batch(fd, NFNL_SUBSYS_NFTABLES, messages, 1);
    netlink::close(fd);
    r
}

pub fn delete_masquerade_rule() -> io::Result<()> {
    let fd = netlink::open(netlink::NETLINK_NETFILTER)?;
    // Deleting the table deletes every chain/rule inside it too -- no
    // need to delete the chain/rule individually first.
    let r = netlink::nft_batch(fd, NFNL_SUBSYS_NFTABLES, vec![del_table_msg()], 1);
    netlink::close(fd);
    r
}

fn new_table_msg() -> Vec<u8> {
    let gen = nfgen(libc::AF_INET as u8);
    let mut b = MsgBuilder::new(msg_type(NFT_MSG_NEWTABLE), 0, as_bytes(&gen));
    b.push_attr_str(NFTA_TABLE_NAME, TABLE_NAME);
    b.finish_raw(msg_type(NFT_MSG_NEWTABLE), 0, 1)
}

fn del_table_msg() -> Vec<u8> {
    let gen = nfgen(libc::AF_INET as u8);
    let mut b = MsgBuilder::new(msg_type(NFT_MSG_DELTABLE), 0, as_bytes(&gen));
    b.push_attr_str(NFTA_TABLE_NAME, TABLE_NAME);
    b.finish_raw(msg_type(NFT_MSG_DELTABLE), 0, 1)
}

fn new_chain_msg() -> Vec<u8> {
    let gen = nfgen(libc::AF_INET as u8);
    let mut b = MsgBuilder::new(msg_type(NFT_MSG_NEWCHAIN), 0, as_bytes(&gen));
    b.push_attr_str(NFTA_CHAIN_TABLE, TABLE_NAME);
    b.push_attr_str(NFTA_CHAIN_NAME, CHAIN_NAME);
    // "type nat hook postrouting priority 100" -- a base chain (has a
    // hook, unlike a plain regular chain), Source-NAT hook point/
    // priority so this only ever runs where SNAT/MASQUERADE is valid.
    b.push_attr_str(NFTA_CHAIN_TYPE, "nat");
    b.nest_start(NFTA_CHAIN_HOOK);
    // Both fields are `__be32` on the wire -- explicit big-endian, not
    // `push_attr_u32` (native/little-endian on x86_64), confirmed by
    // diffing against the real `nft` binary's own encoding of the same
    // "hook postrouting priority 100" via strace.
    b.push_attr(NFTA_HOOK_HOOKNUM, &NF_INET_POST_ROUTING.to_be_bytes());
    b.push_attr(NFTA_HOOK_PRIORITY, &NF_IP_PRI_NAT_SRC.to_be_bytes());
    b.nest_end();
    b.finish_raw(msg_type(NFT_MSG_NEWCHAIN), netlink::NLM_F_CREATE, 2)
}

fn new_rule_msg() -> Vec<u8> {
    let gen = nfgen(libc::AF_INET as u8);
    let mut b = MsgBuilder::new(msg_type(NFT_MSG_NEWRULE), 0, as_bytes(&gen));
    b.push_attr_str(NFTA_RULE_TABLE, TABLE_NAME);
    b.push_attr_str(NFTA_RULE_CHAIN, CHAIN_NAME);
    b.nest_start(NFTA_RULE_EXPRESSIONS);

    // expr 1: "meta iifname" -- load the packet's ingress interface name
    // into NFT_REG_1.
    b.nest_start(NFTA_LIST_ELEM);
    b.push_attr_str(NFTA_EXPR_NAME, "meta");
    b.nest_start(NFTA_EXPR_DATA);
    b.push_attr_u32_be(NFTA_META_DREG, NFT_REG_1);
    b.push_attr_u32_be(NFTA_META_KEY, NFT_META_IIFNAME);
    b.nest_end();
    b.nest_end();

    // expr 2: "== casnet0" -- compare NFT_REG_1 against our host-side
    // veth name, NUL-padded the same way the kernel's own ifname compare
    // data is (exact byte match, not a prefix).
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
    b.finish_raw(msg_type(NFT_MSG_NEWRULE), netlink::NLM_F_CREATE | NLM_F_APPEND, 3)
}
