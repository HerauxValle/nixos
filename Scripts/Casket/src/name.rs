// &desc: "Shared name validation -- non-empty, alnum/-/_/. only, no leading/trailing '.', not '.'/'..'. One place for the check every command that joins a user-supplied name onto a real directory path needs (rootfs environments, backup snapshot names, vault rename targets), instead of each reimplementing or forgetting it -- see docs/known-issues.md-class path-traversal bugs already found and fixed in rootfs (1.10.22) for what skipping this looks like. Tightened from a deny-list (just path separators/null bytes) to an explicit allow-list so names stay safe to embed in external shell tooling (backup wrappers, cron, systemd units) that isn't cas itself -- see Bugs/vault-name-allows-shell-metacharacters.md."
use crate::die;
use crate::error::Result;

/// `what` names the kind of thing being validated (e.g. "rootfs
/// environment", "snapshot", "vault") for the error message.
pub fn validate(what: &str, name: &str) -> Result<()> {
    if name.is_empty() {
        die!("{what} name can't be empty");
    }
    if name == "." || name == ".." {
        die!("'{name}' isn't a valid {what} name");
    }
    if name.starts_with('.') || name.ends_with('.') {
        die!("{what} name '{name}' can't start or end with '.'");
    }
    if !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.') {
        die!("{what} name '{name}' contains an invalid character -- only letters, digits, '-', '_', and '.' are allowed");
    }
    Ok(())
}
