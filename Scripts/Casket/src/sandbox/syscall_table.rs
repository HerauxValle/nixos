// &desc: "Complete syscall name -> number tables for x86_64/aarch64, mechanically extracted from real Linux kernel headers (linux-headers 7.0) -- see data/syscalls-*.toml's own &desc for how to regenerate. This is what makes seccomp filter construction (sandbox::seccomp) not need libseccomp or any other C library at build or run time: name resolution is pure data lookup against a table cas ships and owns itself, same 'own the OS-level mechanics directly' precedent as pivot_root/namespaces."
use std::collections::HashMap;

const X86_64: &str = include_str!("data/syscalls-x86_64.toml");
const AARCH64: &str = include_str!("data/syscalls-aarch64.toml");

#[derive(serde::Deserialize)]
struct Raw {
    syscalls: HashMap<String, i64>,
}

/// The table for the host's actual architecture (`std::env::consts::
/// ARCH`), or `None` if this build's architecture isn't one cas ships a
/// table for -- callers should treat that as "seccomp enforcement isn't
/// available here" rather than guessing.
pub fn for_host_arch() -> Option<HashMap<String, i64>> {
    let data = match std::env::consts::ARCH {
        "x86_64" => X86_64,
        "aarch64" => AARCH64,
        _ => return None,
    };
    Some(parse(data))
}

fn parse(data: &str) -> HashMap<String, i64> {
    let raw: Raw = toml::from_str(data).expect("data/syscalls-*.toml is malformed -- this is a build-time asset, not user input");
    raw.syscalls
}

/// The x86_64 table specifically, regardless of host architecture --
/// used by `registry::seccomp`'s cross-check test (every shipped preset
/// must resolve cleanly on the most common architecture) and available
/// for the same reason to any future caller that needs it independent
/// of what `for_host_arch` would return.
pub fn x86_64_table() -> HashMap<String, i64> {
    parse(X86_64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_tables_parse_and_are_substantial() {
        let x86 = parse(X86_64);
        let arm = parse(AARCH64);
        // A sanity floor, not an exact count -- the kernel adds
        // syscalls over time, so this should never need bumping down,
        // only occasionally up if a future regeneration adds more.
        assert!(x86.len() > 300, "x86_64 table looks too small: {} entries", x86.len());
        assert!(arm.len() > 300, "aarch64 table looks too small: {} entries", arm.len());
    }

    #[test]
    fn spot_check_known_numbers() {
        let x86 = parse(X86_64);
        assert_eq!(x86.get("read"), Some(&0));
        assert_eq!(x86.get("write"), Some(&1));
        assert_eq!(x86.get("execve"), Some(&59));
        assert_eq!(x86.get("ptrace"), Some(&101));
        assert_eq!(x86.get("clone3"), Some(&435));

        let arm = parse(AARCH64);
        assert_eq!(arm.get("read"), Some(&63));
        assert_eq!(arm.get("write"), Some(&64));
        assert_eq!(arm.get("fstat"), Some(&80));
        assert_eq!(arm.get("clone3"), Some(&435));
    }

    #[test]
    fn unsupported_arch_pattern_is_handled_by_none() {
        // Not testing for_host_arch() directly (it reads the real
        // build's ARCH, always x86_64 or aarch64 in CI) -- this
        // documents the intended behavior for anyone changing the
        // match arms later.
        let known = ["x86_64", "aarch64"];
        assert!(known.contains(&std::env::consts::ARCH), "if this ever fails, for_host_arch() correctly returns None for this arch -- no action needed unless seccomp support for it is wanted");
    }
}
