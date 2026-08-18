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
    // Forces the KDL registry's parse + duplicate-id assert to run on
    // every invocation, not just ones that happen to touch a migrated
    // subtree (help/debug/settings/auth/backup/sandbox) -- a session
    // that only ever runs a plain vault-top verb (create/open/exec/...)
    // would otherwise never call `cli_registry::get()` at all, leaving
    // a hypothetical id collision elsewhere in the tree undetected for
    // that whole process. This makes the collision-safety guarantee
    // startup-wide instead of lazy-per-subtree.
    crate::cli_registry::get();

    let mut args: Vec<String> = std::env::args().skip(1).collect();

    let mut ctx = Ctx::default();
    ctx.quiet = pop_flag(&mut args, "--no-log");
    ctx.no_confirm = pop_flag(&mut args, "--no-confirm");
    ctx.debug = pop_flag(&mut args, "--debug");

    if args.is_empty() {
        help::show(&ctx, &[]);
        return Ok(());
    }
    if args[0] == "-h" || args[0] == "--help" {
        help::show(&ctx, &args[1..]);
        return Ok(());
    }
    if args[0] == "help" {
        help::show(&ctx, &args[1..]);
        return Ok(());
    }
    if args[0] == "-V" || args[0] == "--version" || args[0] == "version" {
        println!("cas {}", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }

    let force = pop_flag(&mut args, "--force");
    let remove_keyfile = pop_flag(&mut args, "--removeKeyfile");
    let shred = pop_flag(&mut args, "--shred");
    let test = pop_flag(&mut args, "--test");

    let mut opts = Opts::default();
    opts.pass = pop_value(&mut args, "--pass");
    opts.new_pass = pop_value(&mut args, "--new-pass");
    opts.keyfile = pop_value(&mut args, "--keyfile");
    opts.path = pop_value(&mut args, "--path");
    if let Some(raw) = pop_value(&mut args, "--size") {
        opts.size = Some(parse_size(&raw)?);
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
    if args.first().map(String::as_str) == Some("debug") {
        return commands::debug::dispatch(&ctx, &args[1..]);
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
        let _lock = vault.lock_exclusive()?;
        let meta = Meta::read(&vault.img);
        let effective_kf = opts.keyfile.clone().or_else(|| meta.keyfile.clone());
        let kfm = ensure_keyfile_mounted(&ctx, effective_kf.as_deref().map(Path::new));
        return commands::toggle::run(
            &ctx,
            &vault,
            opts.pass.as_deref(),
            kfm.path.as_deref(),
            effective_kf.as_deref().map(Path::new),
        );
    }

    if args.len() < 2 {
        help::show(&ctx, &[]);
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
            // Lock before create so two concurrent `create`s racing on
            // the same name can't both pass the "already exists" check
            // and stomp each other's `truncate`/`luksFormat`.
            let vault = Vault::resolve(&base, &vault_name);
            let _lock = vault.lock_exclusive()?;
            commands::create::run(&ctx, &base, &vault_name, size, &create_pw, opts.strength, test)
        }

        "open" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let _lock = vault.lock_exclusive()?;
            let meta = Meta::read(&vault.img);
            let effective_kf = opts.keyfile.clone().or_else(|| meta.keyfile.clone());
            let kfm = ensure_keyfile_mounted(&ctx, effective_kf.as_deref().map(Path::new));
            if meta.is_encryption_bypassed() {
                commands::open::run(&ctx, &vault, "", kfm.path.as_deref(), effective_kf.as_deref().map(Path::new))
            } else {
                let pw = prompt::get_pw(&ctx, opts.pass.as_deref())?;
                commands::open::run(&ctx, &vault, &pw, kfm.path.as_deref(), effective_kf.as_deref().map(Path::new))
            }
        }

        "rename" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let _lock = vault.lock_exclusive()?;
            commands::rename::run(&ctx, &vault, &extra)
        }

        "close" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let _lock = vault.lock_exclusive()?;
            commands::close::run(&ctx, &vault, force)
        }

        "toggle" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let _lock = vault.lock_exclusive()?;
            let meta = Meta::read(&vault.img);
            let effective_kf = opts.keyfile.clone().or_else(|| meta.keyfile.clone());
            let kfm = ensure_keyfile_mounted(&ctx, effective_kf.as_deref().map(Path::new));
            commands::toggle::run(
                &ctx,
                &vault,
                opts.pass.as_deref(),
                kfm.path.as_deref(),
                effective_kf.as_deref().map(Path::new),
            )
        }

        "info" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            commands::info::run(&ctx, &vault, opts.pass.as_deref())
        }

        "tampered" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            commands::tampered::run(&ctx, &vault, opts.pass.as_deref())
        }

        "encryption" => die!("moved: cas <vault> settings encryption enable|disable"),

        "passwd" => die!("moved: cas <vault> auth passwd"),

        "2fa" => die!("moved: cas <vault> settings 2fa enable|disable"),

        "auth" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let _lock = vault.lock_exclusive()?;
            commands::auth::dispatch(
                &ctx,
                &vault,
                &extra,
                opts.pass.as_deref(),
                opts.new_pass.as_deref(),
                opts.strength,
                opts.keyfile.as_deref().map(Path::new),
            )
        }

        "backup" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let _lock = vault.lock_exclusive()?;
            commands::backup::dispatch(&ctx, &vault, &extra)
        }

        "settings" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let _lock = vault.lock_exclusive()?;
            commands::settings::dispatch(&ctx, &vault, &extra, opts.pass.as_deref())
        }

        "exec" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let _lock = vault.lock_exclusive()?;
            commands::exec::dispatch(&ctx, &vault, &extra, opts.pass.as_deref())
        }

        "delete" => {
            let vault = Vault::find(&vault_name, path_ref)?;
            let _lock = vault.lock_exclusive()?;
            commands::delete::run(&ctx, &vault, remove_keyfile, shred)
        }

        "resize" | "shrink" => {
            let Some(first) = extra.first() else {
                die!("usage: cas <vault> resize <size>\n    Examples:  cas myvault resize 2048  |  cas myvault resize 20G  |  cas myvault resize 500MiB");
            };
            let size_str = format!("{first}{}", extra.get(1).map(String::as_str).unwrap_or(""));
            let vault = Vault::find(&vault_name, path_ref)?;
            let _lock = vault.lock_exclusive()?;
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
