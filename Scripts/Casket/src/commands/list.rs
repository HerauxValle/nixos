// &desc: "`cas list` — show every vault found nearby, plus any casvault_* mount from /proc/mounts even if it's outside the search path."
use std::collections::HashSet;
use std::path::{Path, PathBuf};

use crate::config::MAPPER_PREFIX;
use crate::ctx::Ctx;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::secret::resolve_lexically;
use crate::vault::is_mountpoint;

pub fn run(ctx: &Ctx, path_override: Option<&Path>) -> Result<()> {
    let mut found: Vec<(String, u64, &'static str, &'static str, String)> = Vec::new();
    let mut seen: HashSet<PathBuf> = HashSet::new();
    let mapper_marker = format!("{MAPPER_PREFIX}_");

    if let Ok(mounts) = std::fs::read_to_string("/proc/mounts") {
        for line in mounts.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() < 2 || !parts[0].contains(&mapper_marker) {
                continue;
            }
            let mnt = PathBuf::from(parts[1]);
            let Some(stem) = mnt.file_name().map(|n| n.to_string_lossy().into_owned()) else {
                continue;
            };
            let img = mnt.with_file_name(format!("{stem}.img"));
            if seen.contains(&img) || !img.exists() {
                continue;
            }
            seen.insert(img.clone());
            let meta = Meta::read(&img);
            let size_mb = img.metadata()?.len() / (1024 * 1024);
            let twofa = if meta.keyfile.is_some() { "2fa" } else { "   " };
            let parent = img.parent().unwrap_or(Path::new(".")).to_string_lossy().into_owned();
            found.push((stem, size_mb, "open  ", twofa, parent));
        }
    }

    let search: Vec<PathBuf> = match path_override {
        Some(p) => vec![resolve_lexically(p)],
        None => {
            let cwd = std::env::current_dir()?;
            let mut v = vec![cwd.clone()];
            v.extend(cwd.ancestors().skip(1).take(4).map(Path::to_path_buf));
            v
        }
    };

    for dir in &search {
        let Ok(entries) = std::fs::read_dir(dir) else { continue };
        let mut imgs: Vec<PathBuf> = entries
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|e| e == "img"))
            .collect();
        imgs.sort();
        for img in imgs {
            if seen.contains(&img) {
                continue;
            }
            seen.insert(img.clone());
            let meta = Meta::read(&img);
            let size_mb = img.metadata()?.len() / (1024 * 1024);
            let stem = img.file_stem().unwrap_or_default().to_string_lossy().into_owned();
            let mnt = img.with_extension("");
            let state = if is_mountpoint(&mnt) { "open  " } else { "closed" };
            let twofa = if meta.keyfile.is_some() { "2fa" } else { "   " };
            let parent = img.parent().unwrap_or(Path::new(".")).to_string_lossy().into_owned();
            found.push((stem, size_mb, state, twofa, parent));
        }
    }

    if found.is_empty() {
        logf!(ctx, "[i] no vaults found (searched cwd and 4 levels up)");
        return Ok(());
    }

    logf!(ctx, "\n  {:<20} {:>8}   {:<8}  {:3}  PATH", "NAME", "SIZE", "STATE", "");
    logf!(ctx, "  {}  {}   {}  {}  {}", "-".repeat(20), "-".repeat(8), "-".repeat(8), "-".repeat(3), "-".repeat(30));
    for (name, size_mb, state, twofa, path) in &found {
        logf!(ctx, "  {name:<20} {size_mb:>7}M   {state:<8}  {twofa:<3}  {path}");
    }
    logf!(ctx);
    Ok(())
}
