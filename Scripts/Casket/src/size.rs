// &desc: "Parses human size strings (20G, 500MiB, 2048) into MiB and formats MiB back into a short label for filesystem/btrfs labels."
use crate::error::{CasError, Result};

/// Parse a size string like "20 GiB", "512mib", "1tb", "2048" into whole
/// MiB. Case-insensitive; a bare number is treated as MiB.
pub fn parse_size(value: &str) -> Result<u64> {
    let trimmed = value.trim();
    let split_at = trimmed
        .find(|c: char| !c.is_ascii_digit() && c != '.')
        .unwrap_or(trimmed.len());
    let (num_str, unit_str) = trimmed.split_at(split_at);
    let unit_str = unit_str.trim().to_ascii_lowercase();

    let num: f64 = num_str.trim().parse().map_err(|_| {
        CasError::new(format!(
            "invalid size '{value}' — examples: 2048, 2048M, 2GiB, 1TB"
        ))
    })?;

    // MiB per unit — 'b' is bytes, everything else is already MiB-based
    // (K/M/G/T and their *ib spellings collapse to the same factor since
    // this tool only ever deals in binary/1024-based units).
    let factor: f64 = match unit_str.as_str() {
        "" => 1.0,
        "b" => 1.0 / 1024.0 / 1024.0,
        "k" | "kb" | "kib" => 1.0 / 1024.0,
        "m" | "mb" | "mib" => 1.0,
        "g" | "gb" | "gib" => 1024.0,
        "t" | "tb" | "tib" => 1024.0 * 1024.0,
        other => {
            return Err(CasError::new(format!(
                "unknown unit '{other}' — use K/M/G/T or KiB/MiB/GiB/TiB"
            )))
        }
    };

    let result = (num * factor) as i64;
    if result < 1 {
        return Err(CasError::new("size too small — minimum is 1 MiB"));
    }
    Ok(result as u64)
}

/// "4096" MiB -> "4 GB", "1536" MiB -> "1.5 GB" — used for btrfs/loop
/// device labels so they show a human size, not a raw MiB count.
pub fn size_label(mb: u64) -> String {
    let gb = mb as f64 / 1024.0;
    if gb == gb.trunc() {
        format!("{} GB", gb as u64)
    } else {
        format!("{gb:.1} GB")
    }
}
