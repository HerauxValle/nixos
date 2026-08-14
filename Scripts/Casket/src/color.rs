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
    paint("33", s) // yellow -- caution, non-fatal ([!]/WARNING: lines)
}

pub fn info(s: &str) -> String {
    paint("36", s) // cyan -- neutral informational ([i] lines)
}

pub fn header(s: &str) -> String {
    paint("1;36", s) // bold cyan -- [section]/ALLCAPS headers
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

pub fn value(s: &str) -> String {
    paint("33", s) // yellow -- a plain data value with no enabled/disabled semantics
}

/// Colors every line of `text` independently -- the single hook every
/// `logf!` call runs through via `Ctx::log`, so the ~70 existing
/// `[✓]`/`[x]`/`[!]`/`[i]`/`WARNING:` call sites across the codebase,
/// plus every static help page's ALLCAPS section headers, get colored
/// output for free without editing each one individually.
pub fn auto(text: &str) -> String {
    text.split('\n').map(auto_line).collect::<Vec<_>>().join("\n")
}

fn auto_line(line: &str) -> String {
    for (marker, paint_fn) in [
        ("[✓]", ok as fn(&str) -> String),
        ("[x]", err as fn(&str) -> String),
        ("[!]", warn as fn(&str) -> String),
        ("[i]", info as fn(&str) -> String),
        ("[cas]", info as fn(&str) -> String),
        ("WARNING:", warn as fn(&str) -> String),
    ] {
        // Only a marker that's the first non-space thing on the line
        // counts -- not one that happens to appear mid-sentence.
        if let Some(idx) = line.find(marker) {
            if line[..idx].chars().all(|c| c == ' ') {
                let (lead, rest) = line.split_at(idx);
                let rest = &rest[marker.len()..];
                return format!("{lead}{}{rest}", paint_fn(marker));
            }
        }
    }

    // A leading "[n/m]" step marker, e.g. luks.rs's "  [1/3] writing new
    // key to slot ...". Short digit/slash brackets only, so this never
    // catches an already-colored "[section]" header (those arrive with
    // an ANSI escape before the bracket, not the bracket itself first).
    let trimmed_start = line.trim_start();
    if let Some(rest) = trimmed_start.strip_prefix('[') {
        if let Some(close) = rest.find(']') {
            let inner = &rest[..close];
            if !inner.is_empty() && inner.len() <= 6 && inner.chars().all(|c| c.is_ascii_digit() || c == '/') {
                let indent = &line[..line.len() - trimmed_start.len()];
                let marker = &trimmed_start[..close + 2];
                let after = &trimmed_start[close + 2..];
                return format!("{indent}{}{after}", info(marker));
            }
        }
    }

    // A line starting (after indent) with a run of uppercase
    // letters/spaces at least 2 characters long is a bare section
    // header in a static help page -- USAGE, "ACTIONS (run on a
    // specific vault)", GLOBAL, OPTIONS, EXAMPLES, TYPICAL FIRST USE, a
    // table header row like "NAME SIZE STATE PATH". Only the leading
    // uppercase run gets colored; anything after it (a parenthetical,
    // lowercase prose) stays plain.
    let trimmed = line.trim_start();
    let indent = &line[..line.len() - trimmed.len()];
    let run_end = trimmed.find(|c: char| !(c.is_ascii_uppercase() || c == ' ')).unwrap_or(trimmed.len());
    let run = trimmed[..run_end].trim_end();
    if run.len() > 1 {
        let rest = &trimmed[run.len()..];
        return format!("{indent}{}{rest}", header(run));
    }

    line.to_string()
}
