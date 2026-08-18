// &desc: "Opt-in real connectivity for a `net`-namespaced exec sandbox -- a veth pair + host-side NAT (MASQUERADE), built from raw rtnetlink/netfilter-netlink messages via netlink.rs (no ip(8)/nft(8) shell-out, no netlink crate). Only active when `settings security sandbox network internet` is enabled on top of the existing `namespaces net` isolation -- without this, `net` still only gets a working loopback (see namespaces::bring_up_loopback), which is the safe, contained default."
use std::io;
use std::mem;
use std::os::unix::io::RawFd;

use super::netlink::{self, MsgBuilder};

// --- rtnetlink (NETLINK_ROUTE) constants -- linux/rtnetlink.h, linux/if_link.h,
// linux/if_addr.h, linux/veth.h. Fixed kernel ABI, same category as
// seccomp.rs's own raw BPF/seccomp constants.
const RTM_NEWLINK: u16 = 16;
const RTM_DELLINK: u16 = 17;
const RTM_GETLINK: u16 = 18;
const RTM_SETLINK: u16 = 19;
const RTM_NEWADDR: u16 = 20;
const RTM_NEWROUTE: u16 = 24;

const IFLA_IFNAME: u16 = 3;
const IFLA_LINKINFO: u16 = 18;
const IFLA_NET_NS_PID: u16 = 19;
const IFLA_INFO_KIND: u16 = 1;
const IFLA_INFO_DATA: u16 = 2;
const VETH_INFO_PEER: u16 = 1;

const IFA_LOCAL: u16 = 2;

const RTA_DST: u16 = 1;
const RTA_OIF: u16 = 4;
const RTA_GATEWAY: u16 = 5;
const RTA_TABLE: u16 = 15;

const RT_TABLE_MAIN: u8 = 254;
const RTPROT_BOOT: u8 = 3;
const RT_SCOPE_UNIVERSE: u8 = 0;
const RT_SCOPE_LINK: u8 = 253;
const RTN_UNICAST: u8 = 1;

/// The subnet this feature always uses for the host<->sandbox veth link
/// -- `10.200.99.0/30` (host `.1`, sandbox `.2`). Fixed rather than
/// dynamically allocated: only one `internet`-enabled `exec` session is
/// supported at a time process-wide (see `Lock` below), so there's
/// nothing to avoid colliding with except the small chance this exact
/// /30 is already used elsewhere on the host, which `setup` surfaces as
/// a plain netlink EEXIST rather than silently misconfiguring routing.
const HOST_IP: [u8; 4] = [10, 200, 99, 1];
const SANDBOX_IP: [u8; 4] = [10, 200, 99, 2];
const PREFIX_LEN: u8 = 30;

const IFACE_HOST: &str = "casnet0";
const IFACE_PEER: &str = "casnet0p";

#[repr(C)]
struct IfInfoMsg {
    family: u8,
    pad: u8,
    ty: u16,
    index: i32,
    flags: u32,
    change: u32,
}

#[repr(C)]
struct IfAddrMsg {
    family: u8,
    prefixlen: u8,
    flags: u8,
    scope: u8,
    index: u32,
}

#[repr(C)]
struct RtMsg {
    family: u8,
    dst_len: u8,
    src_len: u8,
    tos: u8,
    table: u8,
    protocol: u8,
    scope: u8,
    ty: u8,
    flags: u32,
}

fn as_bytes<T>(v: &T) -> &[u8] {
    unsafe { std::slice::from_raw_parts(v as *const T as *const u8, mem::size_of::<T>()) }
}

/// A single process-wide advisory lock (`/run/cas-sandbox-net.lock`)
/// serializing `internet`-enabled `exec` sessions -- the veth pair, IP
/// range, and nft table this module uses are all fixed names/addresses
/// (see `HOST_IP`'s doc comment), so two such sessions running at once
/// (even across different vaults) would silently stomp each other's
/// networking instead of erroring cleanly. Held for the lifetime of the
/// `exec` session; a second concurrent attempt gets a clear "already in
/// use" error instead of corrupting the first session's connectivity.
pub struct Lock(std::fs::File);

pub fn acquire_lock() -> io::Result<Lock> {
    let f = std::fs::OpenOptions::new().create(true).write(true).open("/run/cas-sandbox-net.lock")?;
    let ret = unsafe { libc::flock(std::os::unix::io::AsRawFd::as_raw_fd(&f), libc::LOCK_EX | libc::LOCK_NB) };
    if ret != 0 {
        let e = io::Error::last_os_error();
        if e.kind() == io::ErrorKind::WouldBlock {
            return Err(io::Error::new(io::ErrorKind::WouldBlock, "another 'exec --internet' session is already active"));
        }
        return Err(e);
    }
    Ok(Lock(f))
}

/// Live handle for one `internet`-enabled session -- `teardown` (called
/// once the sandboxed command exits, from `mod.rs::run`) removes
/// everything this created: deleting the host-side veth end also
/// deletes its peer (the kernel always frees a veth pair together), so
/// only the host-side interface and the nft table need explicit
/// cleanup.
pub struct Handle {
    rt_fd: RawFd,
    _lock: Lock,
    ip_forward_was_enabled: bool,
}

/// Runs on every path out of `sandbox::mod::run` while `Handle` still
/// owns cleanup responsibility itself -- i.e. every early-return between
/// `setup_host_side` succeeding and `mod::run` handing the `Handle` off
/// to `spawn_teardown_waiter` (see that function's doc comment for why
/// the handoff has to happen at all, not just rely on this `Drop`
/// unconditionally). Deliberate `Drop` rather than a `teardown()`
/// callers must remember to invoke, same reasoning as `cgroup::Handle`'s
/// own `Drop` impl.
impl Drop for Handle {
    fn drop(&mut self) {
        let _ = nat::delete_masquerade_rule();
        let _ = delete_link(self.rt_fd, IFACE_HOST);
        if !self.ip_forward_was_enabled {
            let _ = std::fs::write("/proc/sys/net/ipv4/ip_forward", b"0");
        }
        netlink::close(self.rt_fd);
        // `_lock` (the flock guard) drops right after this, releasing it
        // for the next session.
    }
}

/// Guard returned by `spawn_teardown_waiter` -- signals the forked
/// helper to run its (already-owned) `Handle`'s teardown and waits for
/// it to finish. `Drop`, same reasoning as `Handle`'s own `Drop`: must
/// fire on every exit path out of `mod::run` from the point it's created
/// onward (success or an early `?`), not just one explicit call site.
pub struct TeardownWaiter {
    write_fd: RawFd,
    helper_pid: libc::pid_t,
}

impl Drop for TeardownWaiter {
    fn drop(&mut self) {
        let go = [0u8; 1];
        unsafe { libc::write(self.write_fd, go.as_ptr() as *const libc::c_void, 1) };
        unsafe { libc::close(self.write_fd) };
        let mut status: libc::c_int = 0;
        unsafe { libc::waitpid(self.helper_pid, &mut status, 0) };
    }
}

/// Hands `handle`'s eventual cleanup off to a forked helper that never
/// enters the restricted user namespace `sandbox::mod::run` unshares
/// into further down (see `namespaces::unshare_user`'s own doc comment
/// on why real root's capabilities don't extend into a child user
/// namespace -- the exact same problem applies here: the netlink calls
/// `Handle`'s teardown needs real capability over the *host* network
/// namespace's objects, which the calling process no longer has once
/// it's inside its own user namespace).
///
/// Must be called *immediately* after `setup_host_side` succeeds --
/// strictly *before* `namespaces::unshare_without_user` (which includes
/// `CLONE_NEWPID`), not just before `unshare_user` as an earlier version
/// of this function did. Forking after entering the new PID namespace
/// makes the fork *itself* claim that namespace's PID-1 slot instead of
/// the sandboxed command that's supposed to get it -- confirmed live
/// (`reaper::run_as_pid1` refused to run, seeing its own pid as 2, not
/// 1). Forking here, before any namespace change, keeps the helper in
/// the original PID namespace entirely, sidestepping the problem.
///
/// `handle` is only borrowed here -- the caller keeps using it normally
/// (`setup_sandbox_side`) afterward. Once genuinely done with it (right
/// before `unshare_user`), call `Handle::detach` to hand real ownership
/// to this already-forked, still-unrestricted helper, which simply
/// blocks on a pipe read until the returned `TeardownWaiter` drops.
pub fn spawn_teardown_waiter(handle: &Handle) -> io::Result<TeardownWaiter> {
    use std::os::unix::io::AsRawFd;

    let mut fds = [0i32; 2];
    if unsafe { libc::pipe(fds.as_mut_ptr()) } != 0 {
        return Err(io::Error::last_os_error());
    }
    let (read_fd, write_fd) = (fds[0], fds[1]);
    let rt_fd = handle.rt_fd;
    let ip_forward_was_enabled = handle.ip_forward_was_enabled;
    let lock_fd = handle._lock.0.as_raw_fd();

    let pid = unsafe { libc::fork() };
    if pid < 0 {
        let e = io::Error::last_os_error();
        unsafe {
            libc::close(read_fd);
            libc::close(write_fd);
        }
        return Err(e);
    }
    if pid == 0 {
        unsafe { libc::close(write_fd) };
        let mut buf = [0u8; 1];
        unsafe { libc::read(read_fd, buf.as_mut_ptr() as *mut libc::c_void, 1) };
        unsafe { libc::close(read_fd) };
        let _ = nat::delete_masquerade_rule();
        let _ = delete_link(rt_fd, IFACE_HOST);
        if !ip_forward_was_enabled {
            let _ = std::fs::write("/proc/sys/net/ipv4/ip_forward", b"0");
        }
        netlink::close(rt_fd);
        unsafe { libc::close(lock_fd) }; // releases the flock now, teardown is done
        std::process::exit(0);
    }
    unsafe { libc::close(read_fd) };
    Ok(TeardownWaiter { write_fd, helper_pid: pid })
}

/// Called once the caller is completely done actively using `handle`
/// (right before `unshare_user`) -- prevents `Handle`'s own `Drop` from
/// also running teardown, since `spawn_teardown_waiter`'s already-forked
/// helper now owns that responsibility. `mem::forget`, not an explicit
/// close of each field: the helper (forked earlier, see that function's
/// doc comment) already holds its own working copies of every fd this
/// needs: closing them here too would pull the rug out from under it.
pub fn detach(handle: Handle) {
    std::mem::forget(handle);
}

/// Runs *before* `namespaces::unshare_without_user` -- needs the host's
/// real network namespace to create the veth pair and see the host's
/// own routing for NAT to work at all. `rt_fd` is deliberately kept open
/// across the later `unshare(CLONE_NEWNET)`: an already-open netlink
/// socket keeps operating against the namespace it was created in even
/// after the owning process moves to a different one (the same
/// principle that lets a process keep writing to an already-open file
/// after `pivot_root`), which is exactly what `move_peer_into_current_ns`
/// below relies on.
pub fn setup_host_side() -> io::Result<Handle> {
    let lock = acquire_lock()?;
    sweep_stale_iface();

    let rt_fd = netlink::open(netlink::NETLINK_ROUTE)?;
    let result = (|| -> io::Result<()> {
        create_veth_pair(rt_fd)?;
        set_addr(rt_fd, IFACE_HOST, HOST_IP)?;
        set_link_up(rt_fd, IFACE_HOST)?;
        Ok(())
    })();
    if let Err(e) = result {
        let _ = delete_link(rt_fd, IFACE_HOST);
        netlink::close(rt_fd);
        return Err(e);
    }

    let ip_forward_was_enabled = read_ip_forward()?;
    if !ip_forward_was_enabled {
        std::fs::write("/proc/sys/net/ipv4/ip_forward", b"1")?;
    }

    if let Err(e) = nat::add_masquerade_rule() {
        let _ = delete_link(rt_fd, IFACE_HOST);
        netlink::close(rt_fd);
        return Err(e);
    }

    Ok(Handle { rt_fd, _lock: lock, ip_forward_was_enabled })
}

/// Runs *after* `unshare(CLONE_NEWNET)` (and after `namespaces::
/// bring_up_loopback`), inside the sandbox's own netns -- moves the veth
/// peer in (using the still-host-bound `rt_fd`, per `setup_host_side`'s
/// doc comment), then finishes configuring it with a fresh netlink
/// socket that *is* bound to the new netns (same pattern as
/// `bring_up_loopback`).
pub fn setup_sandbox_side(handle: &Handle) -> io::Result<()> {
    let self_pid = unsafe { libc::getpid() } as u32;
    move_peer_into_pid(handle.rt_fd, self_pid)?;

    let ns_fd = netlink::open(netlink::NETLINK_ROUTE)?;
    let result = (|| -> io::Result<()> {
        set_addr(ns_fd, IFACE_PEER, SANDBOX_IP)?;
        set_link_up(ns_fd, IFACE_PEER)?;
        add_default_route(ns_fd, IFACE_PEER, HOST_IP)?;
        Ok(())
    })();
    netlink::close(ns_fd);
    result
}

/// Best-effort cleanup of a leftover `casnet0` from a crashed previous
/// run -- `setup_host_side` calls this before creating anything, so a
/// stale interface (which would otherwise make the `NLM_F_EXCL` create
/// below fail with EEXIST) never blocks a fresh session. The `flock`
/// above already prevents this from ever racing a still-live session on
/// this same host.
fn sweep_stale_iface() {
    if let Ok(fd) = netlink::open(netlink::NETLINK_ROUTE) {
        let _ = delete_link(fd, IFACE_HOST);
        netlink::close(fd);
    }
    // Belt-and-suspenders alongside `spawn_teardown_waiter`'s helper
    // process: that helper only fails to run this itself in a
    // catastrophic case (the whole sandboxed process tree killed at
    // once, taking the helper down before it could act -- confirmed
    // reachable live via `pkill -9` against every process in the tree
    // simultaneously). NAT rule creation is idempotent either way
    // (`NLM_F_CREATE`, no `NLM_F_EXCL`), so a stale table wouldn't have
    // blocked a fresh session -- it would just have kept silently
    // accumulating a duplicate masquerade rule per orphaned session
    // instead of ever being noticed.
    let _ = nat::delete_masquerade_rule();
}

fn read_ip_forward() -> io::Result<bool> {
    let s = std::fs::read_to_string("/proc/sys/net/ipv4/ip_forward")?;
    Ok(s.trim() == "1")
}

fn create_veth_pair(fd: RawFd) -> io::Result<()> {
    let ifi = IfInfoMsg { family: 0, pad: 0, ty: 0, index: 0, flags: 0, change: 0 };
    let mut b = MsgBuilder::new(RTM_NEWLINK, 0, as_bytes(&ifi));
    b.push_attr_str(IFLA_IFNAME, IFACE_HOST);
    b.nest_start(IFLA_LINKINFO);
    b.push_attr_str(IFLA_INFO_KIND, "veth");
    b.nest_start(IFLA_INFO_DATA);
    b.nest_start(VETH_INFO_PEER);
    // The peer needs its own (empty) ifinfomsg header inside this nested
    // attribute -- same struct, all-zero, before its own IFLA_IFNAME.
    b_push_raw(&mut b, as_bytes(&ifi));
    b.push_attr_str(IFLA_IFNAME, IFACE_PEER);
    b.nest_end(); // VETH_INFO_PEER
    b.nest_end(); // IFLA_INFO_DATA
    b.nest_end(); // IFLA_LINKINFO
    netlink::request_ack(fd, b, RTM_NEWLINK, netlink::NLM_F_CREATE | netlink::NLM_F_EXCL, 1)
}

/// `MsgBuilder` has no raw-bytes-without-a-TLV-header append -- the veth
/// peer's nested ifinfomsg is the one spot that needs exactly that (it's
/// a fixed struct, not an attribute), so this reaches into the builder's
/// buffer directly rather than adding a one-off method to the shared
/// helper for a single caller.
fn b_push_raw(b: &mut MsgBuilder, data: &[u8]) {
    b.raw(data);
}

fn resolve_ifindex(fd: RawFd, name: &str) -> io::Result<i32> {
    let ifi = IfInfoMsg { family: 0, pad: 0, ty: 0, index: 0, flags: 0, change: 0 };
    let mut b = MsgBuilder::new(RTM_GETLINK, 0, as_bytes(&ifi));
    b.push_attr_str(IFLA_IFNAME, name);
    let msgs = netlink::request_dump_or_single(fd, b, RTM_GETLINK, 2)?;
    for msg in &msgs {
        let hdr_off = 16; // nlmsghdr size
        if hdr_off + mem::size_of::<IfInfoMsg>() > msg.len() {
            continue;
        }
        let index = i32::from_ne_bytes(msg[hdr_off + 4..hdr_off + 8].try_into().unwrap());
        return Ok(index);
    }
    Err(io::Error::new(io::ErrorKind::NotFound, format!("interface '{name}' not found")))
}

fn set_addr(fd: RawFd, iface: &str, ip: [u8; 4]) -> io::Result<()> {
    let index = resolve_ifindex(fd, iface)?;
    let ifa = IfAddrMsg { family: libc::AF_INET as u8, prefixlen: PREFIX_LEN, flags: 0, scope: 0, index: index as u32 };
    let mut b = MsgBuilder::new(RTM_NEWADDR, 0, as_bytes(&ifa));
    b.push_attr(IFA_LOCAL, &ip);
    netlink::request_ack(fd, b, RTM_NEWADDR, netlink::NLM_F_CREATE, 3)
}

fn set_link_up(fd: RawFd, iface: &str) -> io::Result<()> {
    let index = resolve_ifindex(fd, iface)?;
    let ifi = IfInfoMsg { family: 0, pad: 0, ty: 0, index, flags: libc::IFF_UP as u32, change: libc::IFF_UP as u32 };
    let b = MsgBuilder::new(RTM_SETLINK, 0, as_bytes(&ifi));
    netlink::request_ack(fd, b, RTM_SETLINK, 0, 4)
}

fn add_default_route(fd: RawFd, oif_name: &str, gateway: [u8; 4]) -> io::Result<()> {
    let oif = resolve_ifindex(fd, oif_name)?;
    let rt = RtMsg {
        family: libc::AF_INET as u8,
        dst_len: 0,
        src_len: 0,
        tos: 0,
        table: RT_TABLE_MAIN,
        protocol: RTPROT_BOOT,
        scope: RT_SCOPE_UNIVERSE,
        ty: RTN_UNICAST,
        flags: 0,
    };
    let mut b = MsgBuilder::new(RTM_NEWROUTE, 0, as_bytes(&rt));
    b.push_attr(RTA_GATEWAY, &gateway);
    b.push_attr_u32(RTA_OIF, oif as u32);
    netlink::request_ack(fd, b, RTM_NEWROUTE, netlink::NLM_F_CREATE, 5)
}

fn move_peer_into_pid(fd: RawFd, pid: u32) -> io::Result<()> {
    let index = resolve_ifindex(fd, IFACE_PEER)?;
    let ifi = IfInfoMsg { family: 0, pad: 0, ty: 0, index, flags: 0, change: 0 };
    let mut b = MsgBuilder::new(RTM_NEWLINK, 0, as_bytes(&ifi));
    b.push_attr_u32(IFLA_NET_NS_PID, pid);
    netlink::request_ack(fd, b, RTM_NEWLINK, 0, 6)
}

fn delete_link(fd: RawFd, iface: &str) -> io::Result<()> {
    let index = match resolve_ifindex(fd, iface) {
        Ok(i) => i,
        Err(_) => return Ok(()), // already gone -- fine, this is cleanup
    };
    let ifi = IfInfoMsg { family: 0, pad: 0, ty: 0, index, flags: 0, change: 0 };
    let b = MsgBuilder::new(RTM_DELLINK, 0, as_bytes(&ifi));
    netlink::request_ack(fd, b, RTM_DELLINK, 0, 7)
}

/// Silences the unused-import warning for `RT_SCOPE_LINK`/`RTA_DST`/
/// `RTA_TABLE` -- kept defined (accurate kernel constants, documented
/// alongside the ones actually used) for the next person extending this
/// with, say, a narrower scope on the route rather than reused ad hoc.
#[allow(dead_code)]
fn _unused_consts_reference() -> (u8, u16, u16) {
    (RT_SCOPE_LINK, RTA_DST, RTA_TABLE)
}

mod nat;
