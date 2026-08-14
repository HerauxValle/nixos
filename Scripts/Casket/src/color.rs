// &desc: "Global color policy: one place decides whether cas's output gets ANSI color at all (real terminal, no NO_COLOR, not TERM=dumb), and one fixed palette maps meaning -> color everywhere else in the codebase pulls from -- never a hardcoded escape code outside this file."
use std::io::IsTerminal;
use std::sync::OnceLock;

fn enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| {
        if std::env::var_os("NO_COLOR").is_some() {
            return false;
        }
        if std::env::var("TERM").as_deref() == Ok("dumb") {
            return false;
        }
        std::io::stdout().is_terminal()
    })
}

fn paint(code: &str, s: &str) -> String {
    if enabled() {
        format!("\x1b[{code}m{s}\x1b[0m")
    } else {
        s.to_string()
    }
}

/// The fixed meaning -> color palette. Every other module reaches for
/// one of these instead of an ANSI code of its own, so the whole CLI's
/// coloring stays one consistent pattern rather than each command
/// picking colors ad hoc.
pub fn ok(s: &str) -> String {
    paint("32", s) // green -- success ([✓] lines)
}

pub fn err(s: &str) -> String {
    paint("1;31", s) // bold red -- failure ([x] lines)
}

pub fn warn(s: &str) -> String {
    paint("33", s) // yellow -- caution, non-fatal ([!] lines)
}

pub fn info(s: &str) -> String {
    paint("36", s) // cyan -- neutral informational ([i] lines)
}

pub fn header(s: &str) -> String {
    paint("1;36", s) // bold cyan -- [section] headers
}

pub fn name(s: &str) -> String {
    paint("2", s) // dim -- field/setting names (left column)
}

pub fn state(enabled_flag: bool, s: &str) -> String {
    if enabled_flag {
        paint("32", s) // green -- "enabled"
    } else {
        paint("31", s) // red -- "disabled"
    }
}

/// Colors a line by its leading `[✓]`/`[x]`/`[!]`/`[i]` marker, if it has
/// one -- the single hook every `logf!` call runs through via `Ctx::log`,
/// so the ~70 existing call sites across the codebase get colored output
/// for free without editing each one individually.
pub fn auto(line: &str) -> String {
    for (marker, paint_fn) in [
        ("[✓]", ok as fn(&str) -> String),
        ("[x]", err as fn(&str) -> String),
        ("[!]", warn as fn(&str) -> String),
        ("[i]", info as fn(&str) -> String),
    ] {
        if let Some(rest) = line.strip_prefix(marker) {
            return format!("{}{rest}", paint_fn(marker));
        }
        // Indented/newline-led variants, e.g. "  [i] generated keyfile:
        // ..." or "\n[x] aborted".
        if let Some(idx) = line.find(marker) {
            if line[..idx].chars().all(|c| c == ' ' || c == '\n') {
                let (lead, rest) = line.split_at(idx);
                let rest = &rest[marker.len()..];
                return format!("{lead}{}{rest}", paint_fn(marker));
            }
        }
    }
    line.to_string()
}
