// &desc: "Minimal hand-rolled AF_NETLINK request/response plumbing -- raw kernel wire format (linux/netlink.h), no crate. Shared by network.rs's two users: NETLINK_ROUTE (veth/addr/route for sandbox networking) and NETLINK_NETFILTER (the NAT rule). Same philosophy as sandbox/seccomp.rs's own hand-rolled BPF builder -- these are fixed, stable kernel ABI structs, not worth a dependency."
use std::io;
use std::mem;
use std::os::unix::io::RawFd;

pub const NETLINK_ROUTE: libc::c_int = 0;
pub const NETLINK_NETFILTER: libc::c_int = 12;

pub const NLM_F_REQUEST: u16 = 0x0001;
pub const NLM_F_ACK: u16 = 0x0004;
pub const NLM_F_EXCL: u16 = 0x0200;
pub const NLM_F_CREATE: u16 = 0x0400;
pub const NLM_F_DUMP: u16 = 0x0100 | 0x0300; // NLM_F_ROOT | NLM_F_MATCH (dump modifiers)

const NLMSG_ERROR: u16 = 0x0002;
const NLMSG_DONE: u16 = 0x0003;
const NLMSG_ALIGNTO: usize = 4;

fn align(n: usize) -> usize {
    (n + NLMSG_ALIGNTO - 1) & !(NLMSG_ALIGNTO - 1)
}

#[repr(C)]
struct SockaddrNl {
    family: u16,
    pad: u16,
    pid: u32,
    groups: u32,
}

#[repr(C)]
struct NlMsgHdr {
    len: u32,
    ty: u16,
    flags: u16,
    seq: u32,
    pid: u32,
}

/// Opens a netlink socket for the given protocol family (`NETLINK_ROUTE`
/// or `NETLINK_NETFILTER`) and binds it with `pid: 0` -- the kernel
/// assigns a unique per-socket id automatically rather than us using the
/// process pid (multiple sockets in the same process, or a process
/// re-using a pid the kernel already knows about, would otherwise
/// collide).
pub fn open(protocol: libc::c_int) -> io::Result<RawFd> {
    let fd = unsafe { libc::socket(libc::AF_NETLINK, libc::SOCK_RAW, protocol) };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }
    let addr = SockaddrNl { family: libc::AF_NETLINK as u16, pad: 0, pid: 0, groups: 0 };
    let ret = unsafe { libc::bind(fd, &addr as *const SockaddrNl as *const libc::sockaddr, mem::size_of::<SockaddrNl>() as u32) };
    if ret != 0 {
        let e = io::Error::last_os_error();
        unsafe { libc::close(fd) };
        return Err(e);
    }
    Ok(fd)
}

pub fn close(fd: RawFd) {
    unsafe { libc::close(fd) };
}

/// Builds one netlink message: a `nlmsghdr`, a fixed-size family payload
/// (`ifinfomsg`/`ifaddrmsg`/`rtmsg`/`nfgenmsg`, whatever `msg_type` needs),
/// then a TLV attribute stream. Every `push_*` keeps the buffer 4-byte
/// aligned per attribute, matching what the kernel's own parser expects
/// (`NLA_ALIGN`) -- unaligned attributes are silently misparsed, not
/// rejected, so this is the one detail that's fatal to get wrong here.
pub struct MsgBuilder {
    buf: Vec<u8>,
    nest_stack: Vec<usize>,
}

impl MsgBuilder {
    /// `msg_type`/`flags` become the `nlmsghdr`; `payload` is the fixed
    /// per-family header struct (e.g. `ifinfomsg`) serialized by the
    /// caller via `as_bytes` -- attributes are appended after via
    /// `push_attr`/`nest_start`/`nest_end`.
    pub fn new(msg_type: u16, flags: u16, payload: &[u8]) -> Self {
        let mut buf = vec![0u8; mem::size_of::<NlMsgHdr>()];
        buf.extend_from_slice(payload);
        pad_to_align(&mut buf);
        Self { buf, nest_stack: Vec::new() }
    }

    /// One TLV attribute: 4-byte `len`+`type` header, then `data`,
    /// padded so the next attribute starts aligned.
    pub fn push_attr(&mut self, attr_type: u16, data: &[u8]) {
        let len = (4 + data.len()) as u16;
        self.buf.extend_from_slice(&len.to_ne_bytes());
        self.buf.extend_from_slice(&attr_type.to_ne_bytes());
        self.buf.extend_from_slice(data);
        pad_to_align(&mut self.buf);
    }

    pub fn push_attr_u32(&mut self, attr_type: u16, val: u32) {
        self.push_attr(attr_type, &val.to_ne_bytes());
    }

    /// Same as `push_attr_u32` but big-endian (`__be32`) -- nftables
    /// encodes essentially every integer field this way (hook priority/
    /// number, expression register numbers, meta keys, cmp opcodes),
    /// unlike rtnetlink's plain native-order integers. Confirmed by
    /// diffing against the real `nft` binary's own encoding of the same
    /// operations via strace -- using native order here silently builds
    /// a wrong-but-plausible-looking value (e.g. register 1 becomes
    /// 0x01000000 on a little-endian host) that the kernel then rejects
    /// or misinterprets, not a parse error.
    pub fn push_attr_u32_be(&mut self, attr_type: u16, val: u32) {
        self.push_attr(attr_type, &val.to_be_bytes());
    }

    pub fn push_attr_str(&mut self, attr_type: u16, s: &str) {
        let mut data = s.as_bytes().to_vec();
        data.push(0); // NUL-terminated, same as IFLA_IFNAME etc. expect
        self.push_attr(attr_type, &data);
    }

    /// Starts a nested attribute (e.g. `IFLA_LINKINFO`, `IFLA_INFO_DATA`,
    /// nftables' `NFTA_CHAIN_HOOK`/`NFTA_RULE_EXPRESSIONS`/etc.) --
    /// reserves the 4-byte TLV header now, backpatches its length in
    /// `nest_end` once every attribute inside it has been pushed. Always
    /// sets `NLA_F_NESTED` (`0x8000`) on the type -- rtnetlink's own
    /// parser doesn't enforce it (confirmed: the veth/addr/route calls
    /// above worked fine without it), but nftables' *does* strictly
    /// validate it and rejects an otherwise-correct nested attribute
    /// with `EINVAL`/`ENOENT` if it's missing (confirmed by straceing
    /// the real `nft` binary against the same operation). Setting it
    /// unconditionally is harmless for rtnetlink and required for nft,
    /// so there's no reason for callers to opt in per-call. Nesting
    /// stacks freely (`nest_stack` supports it), though nothing here
    /// goes more than two levels deep.
    pub fn nest_start(&mut self, attr_type: u16) {
        const NLA_F_NESTED: u16 = 0x8000;
        let pos = self.buf.len();
        self.buf.extend_from_slice(&0u16.to_ne_bytes()); // length placeholder
        self.buf.extend_from_slice(&(attr_type | NLA_F_NESTED).to_ne_bytes());
        self.nest_stack.push(pos);
    }

    /// Appends raw bytes with no TLV header of their own -- for the one
    /// case where a nested attribute's payload starts with a fixed
    /// struct (the veth peer's own `ifinfomsg`) rather than another
    /// attribute.
    pub fn raw(&mut self, data: &[u8]) {
        self.buf.extend_from_slice(data);
        pad_to_align(&mut self.buf);
    }

    pub fn nest_end(&mut self) {
        let pos = self.nest_stack.pop().expect("nest_end without matching nest_start");
        let len = (self.buf.len() - pos) as u16;
        self.buf[pos..pos + 2].copy_from_slice(&len.to_ne_bytes());
    }

    /// Public alias of `finish` for callers building a message that
    /// isn't sent+acked on its own (e.g. one message inside an nftables
    /// batch, see `nft_batch`) -- everything else here goes through
    /// `request_ack`/`request_dump` instead, which call `finish`
    /// directly since they're in the same module.
    pub fn finish_raw(self, msg_type: u16, flags: u16, seq: u32) -> Vec<u8> {
        self.finish(msg_type, flags, seq)
    }

    /// Finalizes the message: writes the real `nlmsghdr.len` now that the
    /// full size is known, returns the ready-to-send bytes.
    fn finish(mut self, msg_type: u16, flags: u16, seq: u32) -> Vec<u8> {
        assert!(self.nest_stack.is_empty(), "unclosed nest_start");
        let len = self.buf.len() as u32;
        let hdr = NlMsgHdr { len, ty: msg_type, flags: NLM_F_REQUEST | flags, seq, pid: 0 };
        self.buf[0..4].copy_from_slice(&hdr.len.to_ne_bytes());
        self.buf[4..6].copy_from_slice(&hdr.ty.to_ne_bytes());
        self.buf[6..8].copy_from_slice(&hdr.flags.to_ne_bytes());
        self.buf[8..12].copy_from_slice(&hdr.seq.to_ne_bytes());
        self.buf[12..16].copy_from_slice(&hdr.pid.to_ne_bytes());
        self.buf
    }
}

fn pad_to_align(buf: &mut Vec<u8>) {
    let padded = align(buf.len());
    buf.resize(padded, 0);
}

/// Sends one request and waits for its `NLMSGERR` ack -- every call site
/// here uses `NLM_F_ACK`, so a bare `NLMSG_ERROR` with `error == 0` is
/// the *success* ack, not a failure (that's the kernel netlink
/// convention: acks are error messages with error code 0). Anything
/// else (non-zero error, unexpected message type) becomes an `io::Error`
/// so callers can `?` through this like any other syscall wrapper.
pub fn request_ack(fd: RawFd, builder: MsgBuilder, msg_type: u16, flags: u16, seq: u32) -> io::Result<()> {
    let msg = builder.finish(msg_type, flags | NLM_F_ACK, seq);
    send(fd, &msg)?;
    let reply = recv(fd)?;
    parse_ack(&reply, seq)
}

/// Same as `request_ack` but for dump requests (`NLM_F_DUMP`) -- returns
/// every raw message in the multi-part reply (terminated by `NLMSG_DONE`)
/// instead of expecting a single ack, so the caller can walk the results
/// itself (used for the sweep -- listing existing links to find orphans).
pub fn request_dump(fd: RawFd, builder: MsgBuilder, msg_type: u16, seq: u32) -> io::Result<Vec<Vec<u8>>> {
    let msg = builder.finish(msg_type, NLM_F_DUMP, seq);
    send(fd, &msg)?;
    let mut out = Vec::new();
    loop {
        let reply = recv(fd)?;
        let mut offset = 0;
        let mut done = false;
        while offset + mem::size_of::<NlMsgHdr>() <= reply.len() {
            let len = u32::from_ne_bytes(reply[offset..offset + 4].try_into().unwrap()) as usize;
            let ty = u16::from_ne_bytes(reply[offset + 4..offset + 6].try_into().unwrap());
            if len < mem::size_of::<NlMsgHdr>() || offset + len > reply.len() {
                break;
            }
            if ty == NLMSG_DONE {
                done = true;
                break;
            }
            if ty == NLMSG_ERROR {
                let err_off = offset + mem::size_of::<NlMsgHdr>();
                let error = i32::from_ne_bytes(reply[err_off..err_off + 4].try_into().unwrap());
                if error != 0 {
                    return Err(io::Error::from_raw_os_error(-error));
                }
            } else {
                out.push(reply[offset..offset + len].to_vec());
            }
            offset += align(len);
        }
        if done {
            break;
        }
    }
    Ok(out)
}

/// Sends a non-dump request that expects exactly one substantive reply
/// message back (not an ack) -- e.g. `RTM_GETLINK` filtered by
/// `IFLA_IFNAME`, which modern kernels answer with a single `RTM_NEWLINK`
/// reply rather than requiring a full link dump. If the kernel instead
/// replies with `NLMSG_ERROR`, that error is surfaced the same way
/// `request_ack` does. Named `_or_single` (returning a one-element Vec)
/// so call sites can share `request_dump`'s "walk every reply" shape.
pub fn request_dump_or_single(fd: RawFd, builder: MsgBuilder, msg_type: u16, seq: u32) -> io::Result<Vec<Vec<u8>>> {
    let msg = builder.finish(msg_type, 0, seq);
    send(fd, &msg)?;
    let reply = recv(fd)?;
    if reply.len() < mem::size_of::<NlMsgHdr>() {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "netlink reply too short"));
    }
    let ty = u16::from_ne_bytes(reply[4..6].try_into().unwrap());
    if ty == NLMSG_ERROR {
        parse_ack(&reply, seq)?;
        return Ok(Vec::new());
    }
    Ok(vec![reply])
}

/// nftables (`NETLINK_NETFILTER`) rejects a bare individual message the
/// way rtnetlink accepts one -- every table/chain/rule change has to be
/// wrapped in an `NFNL_MSG_BATCH_BEGIN`/`NFNL_MSG_BATCH_END` transaction
/// and sent as a *single* `sendmsg` (confirmed by straceing the real
/// `nft` binary: a bare `NEWTABLE` gets `EINVAL`, the same request
/// wrapped in a batch succeeds). `messages` are pre-built, already-
/// finished individual netlink messages (via `MsgBuilder::finish_raw`);
/// this concatenates them between `BATCH_BEGIN`/`BATCH_END` and sends
/// the result in one write. Only `BATCH_END` carries `NLM_F_ACK` --
/// matching `nft`'s own transaction semantics, the kernel acks (or
/// errors) the whole batch once, keyed to `BATCH_END`'s sequence
/// number, not each message inside it individually.
pub fn nft_batch(fd: RawFd, subsys: u16, messages: Vec<Vec<u8>>, seq_base: u32) -> io::Result<()> {
    const NFNL_MSG_BATCH_BEGIN: u16 = 0x10;
    const NFNL_MSG_BATCH_END: u16 = 0x11;

    #[repr(C)]
    struct NfGenMsg {
        family: u8,
        version: u8,
        res_id_be: [u8; 2],
    }
    let wrapper_payload = NfGenMsg { family: 0, version: 0, res_id_be: subsys.to_be_bytes() };
    let wrapper_bytes: &[u8] = unsafe { std::slice::from_raw_parts(&wrapper_payload as *const NfGenMsg as *const u8, mem::size_of::<NfGenMsg>()) };

    let begin = MsgBuilder::new(NFNL_MSG_BATCH_BEGIN, 0, wrapper_bytes).finish(NFNL_MSG_BATCH_BEGIN, 0, seq_base);
    let end = MsgBuilder::new(NFNL_MSG_BATCH_END, 0, wrapper_bytes).finish(NFNL_MSG_BATCH_END, NLM_F_ACK, seq_base + messages.len() as u32 + 1);

    let mut buf = Vec::new();
    buf.extend_from_slice(&begin);
    for m in &messages {
        buf.extend_from_slice(m);
    }
    buf.extend_from_slice(&end);

    send(fd, &buf)?;
    let reply = recv(fd)?;
    parse_ack(&reply, 0)
}

fn send(fd: RawFd, msg: &[u8]) -> io::Result<()> {
    let n = unsafe { libc::send(fd, msg.as_ptr() as *const libc::c_void, msg.len(), 0) };
    if n < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

fn recv(fd: RawFd) -> io::Result<Vec<u8>> {
    let mut buf = vec![0u8; 32 * 1024];
    let n = unsafe { libc::recv(fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len(), 0) };
    if n < 0 {
        return Err(io::Error::last_os_error());
    }
    buf.truncate(n as usize);
    Ok(buf)
}

fn parse_ack(reply: &[u8], _seq: u32) -> io::Result<()> {
    if reply.len() < mem::size_of::<NlMsgHdr>() + 4 {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "netlink ack too short"));
    }
    let ty = u16::from_ne_bytes(reply[4..6].try_into().unwrap());
    if ty != NLMSG_ERROR {
        return Err(io::Error::new(io::ErrorKind::InvalidData, format!("expected NLMSG_ERROR ack, got type {ty}")));
    }
    let err_off = mem::size_of::<NlMsgHdr>();
    let error = i32::from_ne_bytes(reply[err_off..err_off + 4].try_into().unwrap());
    if error == 0 {
        return Ok(());
    }
    Err(io::Error::from_raw_os_error(-error))
}

/// Finds an attribute of `attr_type` inside a flat (non-nested) TLV
/// stream starting at `offset` in `msg` -- used to read back an
/// interface's ifindex from a dump reply. Returns the attribute's raw
/// payload bytes (header stripped).
pub fn find_attr(msg: &[u8], offset: usize, attr_type: u16) -> Option<&[u8]> {
    let mut pos = offset;
    while pos + 4 <= msg.len() {
        let len = u16::from_ne_bytes(msg[pos..pos + 2].try_into().ok()?) as usize;
        let ty = u16::from_ne_bytes(msg[pos + 2..pos + 4].try_into().ok()?);
        if len < 4 || pos + len > msg.len() {
            break;
        }
        if ty == attr_type {
            return Some(&msg[pos + 4..pos + len]);
        }
        pos += align(len);
    }
    None
}
