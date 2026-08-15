// &desc: "Pure-Rust recursive tree copy + verify, used by fileIntegrity's container migration -- deliberately not a shell-out to rsync/cp: writing the walk ourselves is what makes the live progress bar (percentage, byte counter, current filename) possible, and this codebase already prefers a real Rust construct over another external-binary dependency when one isn't already required."
use std::fs;
use std::io::{IsTerminal, Read, Write};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::ctx::Ctx;
use crate::error::{CasError, Result};

/// One file (or symlink) under a tree root, relative path plus what's
/// needed to copy/compare it.
struct Entry {
    rel: PathBuf,
    is_dir: bool,
    is_symlink: bool,
}

fn walk(root: &Path) -> Vec<Entry> {
    let mut out = Vec::new();
    let mut stack = vec![PathBuf::new()];
    while let Some(rel) = stack.pop() {
        let abs = root.join(&rel);
        let Ok(read) = fs::read_dir(&abs) else { continue };
        for entry in read.filter_map(|e| e.ok()) {
            let rel = rel.join(entry.file_name());
            let Ok(meta) = entry.metadata() else { continue };
            let is_symlink = fs::symlink_metadata(root.join(&rel)).map(|m| m.file_type().is_symlink()).unwrap_or(false);
            let is_dir = meta.is_dir() && !is_symlink;
            if is_dir {
                stack.push(rel.clone());
            }
            out.push(Entry { rel, is_dir, is_symlink });
        }
    }
    out
}

fn total_bytes(root: &Path, entries: &[Entry]) -> u64 {
    entries
        .iter()
        .filter(|e| !e.is_dir && !e.is_symlink)
        .filter_map(|e| fs::metadata(root.join(&e.rel)).ok())
        .map(|m| m.len())
        .sum()
}

/// Human-friendly "x/y" with a single auto-picked unit shared by both
/// numbers (e.g. "219 MiB / 300 MiB", never "219000 KiB / 300 MiB").
fn format_progress(done: u64, total: u64) -> String {
    const UNITS: &[(&str, u64)] = &[("GiB", 1 << 30), ("MiB", 1 << 20), ("KiB", 1 << 10)];
    let (label, div) = UNITS.iter().find(|(_, div)| total >= *div).copied().unwrap_or(("B", 1));
    format!("{:.1} {label} / {:.1} {label}", done as f64 / div as f64, total as f64 / div as f64)
}

struct Progress {
    ctx_quiet: bool,
    tty: bool,
    done: u64,
    total: u64,
    verb: &'static str,
    tick: usize,
}

impl Progress {
    fn new(ctx: &Ctx, total: u64, verb: &'static str) -> Self {
        Progress { ctx_quiet: ctx.quiet, tty: std::io::stdout().is_terminal(), done: 0, total, verb, tick: 0 }
    }

    fn advance(&mut self, added: u64, file: &Path) {
        self.done += added;
        self.draw(file);
    }

    fn draw(&mut self, file: &Path) {
        if self.ctx_quiet {
            return;
        }
        let pct = if self.total == 0 { 100 } else { (self.done * 100 / self.total).min(100) };
        if !self.tty {
            // Piped/non-interactive: a periodic plain line per file, no
            // \r redraw (that only makes sense on a real terminal).
            println!("{pct}%  {}  {}", format_progress(self.done, self.total), file.display());
            return;
        }
        const WIDTH: usize = 30;
        let filled = (WIDTH * pct as usize) / 100;
        let bar = format!("{}{}", "=".repeat(filled), "-".repeat(WIDTH - filled));
        let dots = [".", "..", "...", "..", "."][self.tick % 5];
        self.tick += 1;
        print!(
            "\r\x1b[K{pct:>3}%  [{bar}]  {}\n\x1b[K  {} {}{dots}\x1b[1A\r",
            format_progress(self.done, self.total),
            self.verb,
            file.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
        );
        let _ = std::io::stdout().flush();
    }

    fn finish(&self) {
        if self.ctx_quiet || !self.tty {
            return;
        }
        println!("\r\x1b[K100%  done\x1b[K");
    }
}

fn copy_file(src: &Path, dst: &Path) -> std::io::Result<()> {
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::copy(src, dst)?;
    let meta = fs::metadata(src)?;
    fs::set_permissions(dst, fs::Permissions::from_mode(meta.mode()))?;
    let mtime = filetime::FileTime::from_last_modification_time(&meta);
    filetime::set_file_mtime(dst, mtime)?;
    Ok(())
}

/// Already-copied and unchanged since — same size and mtime as the
/// source. Not a cryptographic guarantee (that's `verify_tree`'s job),
/// just enough to make re-running after an interrupted copy skip work
/// it already did instead of starting a multi-hundred-GB copy over.
fn already_matches(src_meta: &fs::Metadata, dst: &Path) -> bool {
    let Ok(dst_meta) = fs::metadata(dst) else { return false };
    dst_meta.len() == src_meta.len() && dst_meta.mtime() == src_meta.mtime()
}

pub fn copy_tree(ctx: &Ctx, src: &Path, dst: &Path) -> Result<()> {
    let entries = walk(src);
    let total = total_bytes(src, &entries);
    let mut progress = Progress::new(ctx, total, "copying");

    for e in &entries {
        let from = src.join(&e.rel);
        let to = dst.join(&e.rel);
        if e.is_dir {
            fs::create_dir_all(&to)?;
            if let Ok(meta) = fs::metadata(&from) {
                let _ = fs::set_permissions(&to, fs::Permissions::from_mode(meta.mode()));
            }
            continue;
        }
        if e.is_symlink {
            let target = fs::read_link(&from)?;
            let _ = fs::remove_file(&to);
            std::os::unix::fs::symlink(&target, &to)?;
            continue;
        }
        let Ok(meta) = fs::metadata(&from) else { continue };
        if already_matches(&meta, &to) {
            progress.advance(meta.len(), &e.rel);
            continue;
        }
        copy_file(&from, &to).map_err(|err| CasError::new(format!("copying '{}': {err}", e.rel.display())))?;
        progress.advance(meta.len(), &e.rel);
    }
    progress.finish();
    Ok(())
}

fn sha256_file(path: &Path) -> std::io::Result<[u8; 32]> {
    let mut f = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 1 << 16];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hasher.finalize().into())
}

/// Content-level comparison of two trees — not just size/mtime (that's
/// only good enough for the copy pass's resume heuristic). Aborts on
/// the first mismatch found, naming exactly what didn't match; the
/// migration this backs never proceeds to the destructive swap step
/// unless this returns `Ok`.
pub fn verify_tree(ctx: &Ctx, a: &Path, b: &Path) -> Result<()> {
    let entries_a = walk(a);
    let total = total_bytes(a, &entries_a);
    let mut progress = Progress::new(ctx, total, "verifying");

    for e in &entries_a {
        let pa = a.join(&e.rel);
        let pb = b.join(&e.rel);
        if e.is_dir {
            if !pb.is_dir() {
                return Err(CasError::new(format!("verify failed: '{}' missing on the new side", e.rel.display())));
            }
            continue;
        }
        if e.is_symlink {
            let (ta, tb) = (fs::read_link(&pa), fs::read_link(&pb));
            if ta.ok() != tb.ok() {
                return Err(CasError::new(format!("verify failed: symlink '{}' doesn't match", e.rel.display())));
            }
            continue;
        }
        let Ok(meta) = fs::metadata(&pa) else { continue };
        if !pb.is_file() {
            return Err(CasError::new(format!("verify failed: '{}' missing on the new side", e.rel.display())));
        }
        let (ha, hb) = (sha256_file(&pa), sha256_file(&pb));
        match (ha, hb) {
            (Ok(ha), Ok(hb)) if ha == hb => {}
            _ => return Err(CasError::new(format!("verify failed: '{}' content doesn't match", e.rel.display()))),
        }
        progress.advance(meta.len(), &e.rel);
    }
    progress.finish();

    // Catch anything present on the new side that isn't on the old one
    // too -- shouldn't happen (nothing else should be writing to the
    // staging mount during migration), but worth confirming rather than
    // assuming.
    let entries_b = walk(b);
    if entries_b.len() != entries_a.len() {
        return Err(CasError::new(format!(
            "verify failed: entry count mismatch ({} old vs {} new) — something wrote to the new container during migration",
            entries_a.len(),
            entries_b.len()
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn copy_then_verify_then_resume_skips_and_detects_tamper() {
        let ctx = Ctx { quiet: true, no_confirm: false, debug: false };
        let tmp = std::env::temp_dir().join(format!("cas-migrate-test-{}", std::process::id()));
        let src = tmp.join("src");
        let dst = tmp.join("dst");
        fs::create_dir_all(src.join("subdir")).unwrap();
        fs::write(src.join("a.bin"), vec![7u8; 50_000]).unwrap();
        fs::write(src.join("subdir/b.bin"), vec![9u8; 30_000]).unwrap();
        fs::write(src.join("text.txt"), "hello").unwrap();
        std::os::unix::fs::symlink("text.txt", src.join("link.txt")).unwrap();

        copy_tree(&ctx, &src, &dst).unwrap();
        verify_tree(&ctx, &src, &dst).unwrap();

        // Resume: re-running copy_tree should skip everything (same
        // size+mtime) without erroring.
        copy_tree(&ctx, &src, &dst).unwrap();
        verify_tree(&ctx, &src, &dst).unwrap();

        // Tamper detection: corrupt one byte on the dst side only.
        let mut bytes = fs::read(dst.join("a.bin")).unwrap();
        bytes[0] ^= 0xFF;
        fs::write(dst.join("a.bin"), bytes).unwrap();
        assert!(verify_tree(&ctx, &src, &dst).is_err());

        let _ = fs::remove_dir_all(&tmp);
    }
}
