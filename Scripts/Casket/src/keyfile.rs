// &desc: "Keyfile storage: a keyfile is either raw (the whole file is the key bytes, today's format, untouched) or embedded (key bytes in a tagged trailer appended to an otherwise-arbitrary carrier file, own magic distinct from the vault's). read_bytes() is the one reader every keyfile-consuming path should use so embedded keyfiles just work anywhere a raw one did."
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

const MAGIC: [u8; 8] = *b"CASKEY01";
const MAGIC_LEN: usize = MAGIC.len();
const FIXED_LEN: i64 = MAGIC_LEN as i64 + 4;

/// Same shape/logic as meta::locate, generalized to any carrier file and
/// this module's own magic — a vault trailer and a keyfile trailer on
/// the same file coexist harmlessly, each only checking its own tag.
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
    if file_len < FIXED_LEN as u64 {
        return None;
    }
    let mut len_buf = [0u8; 4];
    f.seek(SeekFrom::End(-FIXED_LEN)).ok()?;
    f.read_exact(&mut len_buf).ok()?;
    let size = u32::from_be_bytes(len_buf);
    let payload_start = (file_len as i64) - FIXED_LEN - size as i64;
    if payload_start < 0 {
        return None;
    }
    Some((payload_start as u64, size))
}

/// True if `path`'s last 8 bytes are the keyfile magic — carries an
/// embedded trailer rather than being a raw standalone key.
pub fn is_embedded(path: &Path) -> bool {
    File::open(path).ok().as_mut().and_then(locate).is_some()
}

/// Read just the trailer payload (the raw key bytes) from a carrier.
pub fn read_embedded(path: &Path) -> std::io::Result<Vec<u8>> {
    let mut f = File::open(path)?;
    let (start, size) = locate(&mut f)
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "no embedded keyfile trailer found"))?;
    let mut buf = vec![0u8; size as usize];
    f.seek(SeekFrom::Start(start))?;
    f.read_exact(&mut buf)?;
    Ok(buf)
}

/// The key bytes at `path`, whichever form it's in: embedded trailer if
/// present, otherwise the whole file treated as a raw keyfile (today's
/// format, unchanged). This is the one reader every keyfile-consuming
/// path (open, passwd, settings::encryption/twofa, gate) should call.
pub fn read_bytes(path: &Path) -> std::io::Result<Vec<u8>> {
    if is_embedded(path) {
        read_embedded(path)
    } else {
        std::fs::read(path)
    }
}

/// Strip any existing keyfile trailer from `path` (no-op if none).
fn strip(path: &Path) -> std::io::Result<()> {
    let mut f = match OpenOptions::new().read(true).write(true).open(path) {
        Ok(f) => f,
        Err(_) => return Ok(()),
    };
    if let Some((start, _)) = locate(&mut f) {
        f.set_len(start)?;
    }
    Ok(())
}

/// Strip any existing trailer, then append `key_bytes` as a new one.
/// `path` doesn't need to exist yet — embedding into a fresh empty file
/// is just that file's whole content becoming the trailer.
pub fn write_embedded(path: &Path, key_bytes: &[u8]) -> std::io::Result<()> {
    strip(path)?;
    let mut f = OpenOptions::new().create(true).append(true).open(path)?;
    f.write_all(key_bytes)?;
    f.write_all(&(key_bytes.len() as u32).to_be_bytes())?;
    f.write_all(&MAGIC)?;
    Ok(())
}

/// Remove an existing trailer, restoring the carrier to its pre-embed
/// bytes. Returns `false` (no-op) if there wasn't one.
pub fn strip_embedded(path: &Path) -> std::io::Result<bool> {
    let mut f = OpenOptions::new().read(true).write(true).open(path)?;
    match locate(&mut f) {
        Some((start, _)) => {
            f.set_len(start)?;
            Ok(true)
        }
        None => Ok(false),
    }
}
