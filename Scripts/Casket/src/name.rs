// &desc: "Shared path-safe name validation -- non-empty, no path separators/null bytes, not '.'/'..'. One place for the check every command that joins a user-supplied name onto a real directory path needs (rootfs environments, backup snapshot names, vault rename targets), instead of each reimplementing or forgetting it -- see docs/known-issues.md-class path-traversal bugs already found and fixed in rootfs (1.10.22) for what skipping this looks like."
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
    if name.contains('/') || name.contains('\\') || name.contains('\0') {
        die!("{what} name '{name}' contains an invalid character -- no path separators allowed");
    }
    Ok(())
}
