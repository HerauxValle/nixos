// &desc: "Interactive input: default-aware line prompts, hidden passphrase entry, and the --pass/stdin/prompt precedence chain — all suppressed when --no-log is set."
use std::io::{self, IsTerminal, Read, Write};
use std::path::Path;

use crate::ctx::Ctx;
use crate::error::{CasError, Result};
use crate::logf;

/// Prompt for a line of input, returning `default` (or "") if the user
/// enters nothing. Mirrors the original `ask(prompt, default)`.
pub fn ask(ctx: &Ctx, prompt: &str, default: Option<&str>) -> Result<String> {
    if !ctx.quiet {
        match default {
            Some(d) => print!("{prompt} [{d}]: "),
            None => print!("{prompt}: "),
        }
        let _ = io::stdout().flush();
    }
    let mut line = String::new();
    io::stdin().read_line(&mut line).map_err(|_| aborted())?;
    let val = line.trim();
    Ok(if val.is_empty() {
        default.unwrap_or("").to_string()
    } else {
        val.to_string()
    })
}

/// Prompt for a line of input with no echo (passphrases, keyfile PINs).
pub fn ask_secret(ctx: &Ctx, prompt: &str) -> Result<String> {
    if !ctx.quiet {
        print!("{prompt}: ");
        let _ = io::stdout().flush();
    }
    rpassword::read_password().map_err(|_| aborted())
}

/// Ask the user to type `expected` back to confirm a destructive action.
/// Skipped (auto-confirmed) under --no-log or --no-confirm, matching the
/// original's `QUIET or NO_CONFIRM` shortcut.
pub fn confirm_name(ctx: &Ctx, expected: &str, warning: &str) -> Result<bool> {
    confirm_named(ctx, expected, "vault", warning)
}

/// Same as `confirm_name`, but for confirming something other than the
/// vault itself (e.g. a rootfs environment's name) -- `noun` fills in
/// what the prompt says is being confirmed, so typing the wrong thing
/// (or the vault's name by habit, when an environment's name was
/// wanted) doesn't silently pass.
pub fn confirm_named(ctx: &Ctx, expected: &str, noun: &str, warning: &str) -> Result<bool> {
    if ctx.quiet || ctx.no_confirm {
        return Ok(true);
    }
    logf!(ctx, "  [!] {warning}");
    let typed = ask(ctx, &format!("  Type the {noun} name '{expected}' to confirm"), None)?;
    Ok(typed == expected)
}

/// Plain yes/no prompt, defaulting to "no" on empty input (a rebuild is
/// real disk work with a nonzero blast radius -- silence shouldn't be
/// read as consent). Auto-confirmed under `--no-log`/`--no-confirm`,
/// same shortcut `confirm_named` already uses, so scripted/automated
/// callers aren't blocked -- they just get the work done instead of
/// hanging on stdin.
pub fn confirm_yes_no(ctx: &Ctx, question: &str) -> Result<bool> {
    if ctx.quiet || ctx.no_confirm {
        return Ok(true);
    }
    let ans = ask(ctx, &format!("{question} [y/N]"), Some("n"))?;
    Ok(matches!(ans.trim().to_lowercase().as_str(), "y" | "yes"))
}

fn aborted() -> CasError {
    println!("\n{}", crate::color::auto("[x] aborted"));
    CasError::Silent
}

/// Quote `s` for safe reuse in a shell command line, using the same
/// "leave simple tokens bare, single-quote everything else" strategy as
/// Python's `shlex.quote`.
fn shell_quote(s: &str) -> String {
    let safe = !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || "@%_-+=:,./".contains(c));
    if safe {
        s.to_string()
    } else {
        format!("'{}'", s.replace('\'', "'\\''"))
    }
}

/// Resolve the passphrase to use, in order: an explicit `--pass` value
/// (or, if that value happens to be an existing file, its contents),
/// then piped stdin, then an interactive hidden prompt.
pub fn get_pw(ctx: &Ctx, explicit: Option<&str>) -> Result<String> {
    if let Some(explicit) = explicit {
        logf!(ctx, "[!] --pass in shell args is visible in your shell history.");

        let args: Vec<String> = std::env::args().collect();
        let mut hint_parts = Vec::with_capacity(args.len());
        let mut skip_next = false;
        for a in &args {
            if skip_next {
                skip_next = false;
                continue;
            }
            if a == "--pass" {
                skip_next = true;
                continue;
            }
            hint_parts.push(shell_quote(a));
        }
        logf!(ctx, "  [i] use stdin instead:");
        logf!(
            ctx,
            "      printf %s {} | {}",
            shell_quote(explicit),
            hint_parts.join(" ")
        );

        let p = Path::new(explicit);
        if p.is_file() {
            return Ok(std::fs::read_to_string(p)?.trim().to_string());
        }
        return Ok(explicit.to_string());
    }

    if !io::stdin().is_terminal() {
        let mut data = String::new();
        io::stdin().read_to_string(&mut data)?;
        if !data.is_empty() {
            return Ok(data.trim_end_matches('\n').to_string());
        }
    }

    ask_secret(ctx, "passphrase")
}
