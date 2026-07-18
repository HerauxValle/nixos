// &desc: "Run context threaded through every command: output verbosity and the confirmation-skip flag, replacing the original's global QUIET/NO_CONFIRM."

#[derive(Debug, Clone, Copy, Default)]
pub struct Ctx {
    /// Set by --no-log. Suppresses all `[i]`/`[✓]`/`[x]` output but never
    /// changes control flow — a quiet failure still exits 1.
    pub quiet: bool,
    /// Set by --no-confirm. Skips "type the vault name to confirm" prompts
    /// on destructive actions (delete, shrink, restore).
    pub no_confirm: bool,
}

impl Ctx {
    #[inline]
    pub fn log(&self, args: std::fmt::Arguments) {
        if !self.quiet {
            println!("{args}");
        }
    }
}

/// `logf!(ctx, "...", args)` — println! that respects `ctx.quiet`, replacing
/// the original's `log()` helper.
#[macro_export]
macro_rules! logf {
    ($ctx:expr) => {
        $ctx.log(format_args!(""))
    };
    ($ctx:expr, $($arg:tt)*) => {
        $ctx.log(format_args!($($arg)*))
    };
}
