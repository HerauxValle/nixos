// &desc: "Run context threaded through every command: output verbosity and the confirmation-skip flag, replacing the original's global QUIET/NO_CONFIRM."

#[derive(Debug, Clone, Copy, Default)]
pub struct Ctx {
    /// Set by --no-log. Suppresses all `[i]`/`[✓]`/`[x]` output but never
    /// changes control flow — a quiet failure still exits 1.
    pub quiet: bool,
    /// Set by --no-confirm. Skips "type the vault name to confirm" prompts
    /// on destructive actions (delete, shrink, restore).
    pub no_confirm: bool,
    /// Set by --debug. Prints `[debug]`-prefixed diagnostic lines
    /// (internal step tracing, e.g. sandbox::run's syscall sequence)
    /// that are silent otherwise -- never gated by `quiet`, since
    /// someone passing --debug wants to see it regardless.
    pub debug: bool,
}

impl Ctx {
    #[inline]
    pub fn log(&self, args: std::fmt::Arguments) {
        if !self.quiet {
            println!("{}", crate::color::auto(&args.to_string()));
        }
    }

    #[inline]
    pub fn debug_log(&self, args: std::fmt::Arguments) {
        if self.debug {
            println!("{}", crate::color::auto(&format!("[debug] {args}")));
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

/// `debugf!(ctx, "...", args)` — println! gated on `ctx.debug`
/// (`--debug`), prefixed `[debug]`. Silent unless `--debug` is passed,
/// regardless of `--no-log`.
#[macro_export]
macro_rules! debugf {
    ($ctx:expr, $($arg:tt)*) => {
        $ctx.debug_log(format_args!($($arg)*))
    };
}
