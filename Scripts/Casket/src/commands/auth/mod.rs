// &desc: "Module hub for `cas <vault> auth ...` -- identity material (passphrase, keyfile) as opposed to settings/ (behavior toggles). passwd has its own arg shape (old/new/strength) so cli.rs routes it directly; keyfile's sub-dispatch lives in keyfile/mod.rs."
pub mod keyfile;
pub mod passwd;
