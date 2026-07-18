// &desc: "Flag scanner (mirrors the original's pop_opt) plus the vault/action dispatch that used to be main()'s if-elif chain, now one match arm per commands::* module."
use std::path::Path;

use crate::commands;
use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::{CasError, Result};
use crate::help;
use crate::keyfile_mount::ensure_keyfile_mounted;
use crate::logf;
use crate::meta::Meta;
use crate::prompt;
use crate::secret::resolve_lexically;
use crate::size::parse_size;
use crate::vault::Vault;

#[derive(Default)]
struct Opts {
    pass: Option<String>,
    new_pass: Option<String>,
    keyfile: Option<String>,
    size: Option<u64>,
    strength: Strength,
    path: Option<String>,
}

fn pop_value(args: &mut Vec<String>, flag: &str) -> Option<String> {
    let i = args.iter().position(|a| a == flag)?;
    args.remove(i);
    (i < args.len()).then(|| args.remove(i))
}

fn pop_flag(args: &mut Vec<String>, flag: &str) -> bool {
    match args.iter().position(|a| a == flag) {
        Some(i) => {
            args.remove(i);
            true
        }
        None => false,
    }
}

pub fn run() -> Result<()> {
    let mut args: Vec<String> = std::env::args().skip(1).collect();

    let mut ctx = Ctx::default();
    ctx.quiet = pop_flag(&mut args, "--no-log");
    ctx.no_confirm = pop_flag(&mut args, "--no-confirm");

    if args.is_empty() || args[0] == "-h" || args[0] == "--help" {
        help::show(&ctx, None);
        return Ok(());
    }
    if args[0] == "help" {
        help::show(&ctx, args.get(1).map(String::as_str));
        return Ok(());
    }

    let mut opts = Opts::default();
    opts.pass = pop_value(&mut args, "--pass");
    opts.new_pass = pop_value(&mut args, "--new-pass");
    opts.keyfile = pop_value(&mut args, "--keyfile");
    opts.path = pop_value(&mut args, "--path");
    if let Some(raw) = pop_value(&mut args, "--size") {
        opts.size = Some(raw.parse::<u64>().map_err(|_| CasError::new(format!("invalid --size '{raw}'")))?);
    }
    if let Some(raw) = pop_value(&mut args, "--strength") {
        opts.strength = raw.parse::<Strength>().map_err(CasError::Msg)?;
    }
    let path_ref = opts.path.as_deref().map(Path::new);

    if args.first().map(String::as_str) == Some("list") {
        return commands::list::run(&ctx, path_ref);
    }
    if args.len() >= 2 && args[0] == "all" && args[1] == "close" {
        return commands::close_all::run(&ctx);
    }
    if args.first().map(String::as_str) == Some("quit") {
        return commands::close_all::run(&ctx);
    }

    // cas path/to/vault.img  (bare path toggle)
    if args.len() == 1 && (args[0].ends_with(".img") || args[0].contains(std::path::MAIN_SEPARATOR)) {
        let p = resolve_lexically(Path::new(&args[0]));
        if !p.exists() {
            die!("file not found: {}", p.display());
        }
        let name = p.file_stem().unwrap_or_default().to_string_lossy().into_owned();
        let base = p.parent().unwrap_or(Path::new(".")).to_path_buf();
        let vault = Vault::resolve(&base, &name);
        let kfm = ensure_keyfile_mounted(&ctx, opts.keyfile.as_deref().map(Path::new));
        return commands::toggle::run(&ctx, &vault, opts.pass.as_deref(), kfm.path.as_deref());
    }

    if args.len() < 2 {
        help::show(&ctx, None);
        return Ok(());
    }

    let vault_name = args[0].clone();
    let action = args[1].clone();
    let extra = args[2..].to_vec();

    match action.as_str() {
        "create" => {
            let base = resolve_lexically(Path::new(opts.path.as_deref().unwrap_or(".")));
            let size = match opts.size {
                Some(s) => Some(s),
                None if opts.pass.is_none() => {
                    Some(parse_size(&prompt::ask(&ctx, "size (e.g. 1G, 500M, 2048)", Some("1G"))?)?)
                }
                None => None,
            };
            let create_pw = match opts.pass.as_deref() {
                Some(p) if !p.is_empty() => prompt::get_pw(&ctx, Some(p))?,
                _ => prompt::ask_secret(&ctx, "passphrase (leave empty to generate a strong one)")?,
            };
            commands::create::run(&ctx, &base, &vault_name, size, &create_pw, opts.strength)
        }

        "open" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let meta = Meta::read(&vault.img);
            let effective_kf = opts.keyfile.clone().or_else(|| meta.keyfile.clone());
            let kfm = ensure_keyfile_mounted(&ctx, effective_kf.as_deref().map(Path::new));
            if meta.is_encryption_bypassed() {
                commands::open::run(&ctx, &vault, "", kfm.path.as_deref())
            } else {
                let pw = prompt::get_pw(&ctx, opts.pass.as_deref())?;
                commands::open::run(&ctx, &vault, &pw, kfm.path.as_deref())
            }
        }

        "rename" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            commands::rename::run(&ctx, &vault, &extra)
        }

        "close" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            commands::close::run(&ctx, &vault)
        }

        "toggle" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let kfm = ensure_keyfile_mounted(&ctx, opts.keyfile.as_deref().map(Path::new));
            commands::toggle::run(&ctx, &vault, opts.pass.as_deref(), kfm.path.as_deref())
        }

        "info" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            commands::info::run(&ctx, &vault)
        }

        "encryption" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let sub = extra.first().map(String::as_str).unwrap_or("");
            let pw = prompt::get_pw(&ctx, opts.pass.as_deref())?;
            commands::encryption::dispatch(&ctx, &vault, sub, &pw)
        }

        "passwd" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let old_pw = prompt::get_pw(&ctx, opts.pass.as_deref())?;
            let strength = (opts.strength != Strength::Medium).then_some(opts.strength);
            commands::passwd::run(&ctx, &vault, &old_pw, opts.new_pass.as_deref(), strength)
        }

        "2fa" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let sub = extra.first().map(String::as_str).unwrap_or("");
            let pw = prompt::get_pw(&ctx, opts.pass.as_deref())?;
            commands::twofa::dispatch(&ctx, &vault, sub, &pw)
        }

        "backup" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            commands::backup::dispatch(&ctx, &vault, &extra)
        }

        "delete" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            commands::delete::run(&ctx, &vault)
        }

        "resize" | "shrink" => {
            let Some(first) = extra.first() else {
                die!("usage: cas <vault> resize <size>\n    Examples:  cas myvault resize 2048  |  cas myvault resize 20G  |  cas myvault resize 500MiB");
            };
            let size_str = format!("{first}{}", extra.get(1).map(String::as_str).unwrap_or(""));
            let vault = Vault::find(&vault_name, path_ref)?;
            let new_mb = parse_size(&size_str)?;
            let pw = prompt::get_pw(&ctx, opts.pass.as_deref())?;
            commands::resize::run(&ctx, &vault, new_mb, &pw)
        }

        other => {
            logf!(&ctx, "[x] unknown action '{other}'");
            logf!(&ctx, "    run 'cas help' to see all commands");
            std::process::exit(1);
        }
    }
}
