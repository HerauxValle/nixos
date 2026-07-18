// &desc: "Shared error type for cas: a user-facing message (printed as `[x] ...`) or a silent failure whose message was already shown."
use std::fmt;

/// Every fallible operation in cas returns `Result<T, CasError>`. `Msg`
/// carries a message that main() prints with the `[x]` prefix the
/// original tool used (and honors --no-log the same way `die()` did);
/// `Silent` is for the few paths — like Ctrl-C during a prompt — that
/// already printed their own message and just need the process to exit 1.
#[derive(Debug)]
pub enum CasError {
    Msg(String),
    Silent,
}

pub type Result<T> = std::result::Result<T, CasError>;

impl CasError {
    pub fn new(msg: impl Into<String>) -> Self {
        CasError::Msg(msg.into())
    }
}

impl fmt::Display for CasError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CasError::Msg(s) => write!(f, "{s}"),
            CasError::Silent => Ok(()),
        }
    }
}

impl From<std::io::Error> for CasError {
    fn from(e: std::io::Error) -> Self {
        CasError::Msg(e.to_string())
    }
}

impl From<serde_json::Error> for CasError {
    fn from(e: serde_json::Error) -> Self {
        CasError::Msg(e.to_string())
    }
}

/// Early-return a `CasError::Msg` built from a format string, mirroring
/// every `die(f"...")` call site in the Python original.
#[macro_export]
macro_rules! die {
    ($($arg:tt)*) => {
        return Err($crate::error::CasError::new(format!($($arg)*)))
    };
}
