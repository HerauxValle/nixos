// &desc: "Reads/writes the vault's trailing metadata block: [JSON][4-byte BE length][8-byte magic], appended after the LUKS container — byte-compatible with the Python original."
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::config::{MAGIC, MAGIC_LEN};

/// Fixed part of the trailer: the 4-byte length prefix plus the magic.
const TRAILER_FIXED_LEN: i64 = MAGIC_LEN as i64 + 4;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Meta {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub keyfile: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub encrypted: Option<bool>,
    #[serde(rename = "_autokey", skip_serializing_if = "Option::is_none")]
    pub autokey: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub backup_auto: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub backup_auto_keep: Option<u32>,
}

/// Find the trailer on an open handle. Returns `(payload_start_offset,
/// payload_len)` from the start of the file, or `None` if the file is too
/// short or the trailing 8 bytes don't match `MAGIC` — an untagged image.
fn locate(f: &mut File) -> Option<(u64, u32)> {
    let file_len = f.metadata().ok()?.len();
    if file_len < MAGIC_LEN as u64 {
        return None;
    }
    let mut magic_buf = [0u8; MAGIC_LEN];
    f.seek(SeekFrom::End(-(MAGIC_LEN as i64))).ok()?;
    f.read_exact(&mut magic_buf).ok()?;
    if magic_buf != MAGIC {
        return None;
    }
    if file_len < TRAILER_FIXED_LEN as u64 {
        return None;
    }
    let mut len_buf = [0u8; 4];
    f.seek(SeekFrom::End(-TRAILER_FIXED_LEN)).ok()?;
    f.read_exact(&mut len_buf).ok()?;
    let size = u32::from_be_bytes(len_buf);
    let payload_start = (file_len as i64) - TRAILER_FIXED_LEN - size as i64;
    if payload_start < 0 {
        return None;
    }
    Some((payload_start as u64, size))
}

impl Meta {
    /// Read the trailing metadata block. Any failure — no trailer, a
    /// truncated one, or malformed JSON — is treated as "no metadata",
    /// mirroring the original's blanket `except Exception: return {}`.
    pub fn read(img: &Path) -> Meta {
        (|| -> Option<Meta> {
            let mut f = File::open(img).ok()?;
            let (start, size) = locate(&mut f)?;
            let mut buf = vec![0u8; size as usize];
            f.seek(SeekFrom::Start(start)).ok()?;
            f.read_exact(&mut buf).ok()?;
            serde_json::from_slice(&buf).ok()
        })()
        .unwrap_or_default()
    }

    /// Truncate away an existing trailer, if present. No-op if the file
    /// can't be opened or carries no trailer. Must run before any LUKS
    /// operation — cryptsetup treats the whole file as a raw block device
    /// and would otherwise see the trailer as part of its own data.
    pub fn strip(img: &Path) -> std::io::Result<()> {
        let mut f = match OpenOptions::new().read(true).write(true).open(img) {
            Ok(f) => f,
            Err(_) => return Ok(()),
        };
        if let Some((start, _)) = locate(&mut f) {
            f.set_len(start)?;
        }
        Ok(())
    }

    /// Strip any existing trailer, then append this metadata as the new
    /// one. Always stripping first means repeated writes never stack.
    pub fn write(&self, img: &Path) -> std::io::Result<()> {
        Self::strip(img)?;
        let payload = serde_json::to_vec(self).unwrap_or_default();
        let mut f = OpenOptions::new().append(true).open(img)?;
        f.write_all(&payload)?;
        f.write_all(&(payload.len() as u32).to_be_bytes())?;
        f.write_all(&MAGIC)?;
        Ok(())
    }

    pub fn has_2fa(&self) -> bool {
        self.keyfile.is_some()
    }

    pub fn is_encryption_bypassed(&self) -> bool {
        self.encrypted == Some(false) && self.autokey.is_some()
    }

    pub fn backup_auto_keep_or(&self, default: u32) -> u32 {
        self.backup_auto_keep.unwrap_or(default)
    }
}
