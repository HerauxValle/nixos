// &desc: "Module hub for every `cas` action — one file per command, each exposing its own run()/dispatch() so adding an action means adding a file plus one match arm in cli.rs."
pub mod backup;
pub mod close;
pub mod close_all;
pub mod create;
pub mod delete;
pub mod encryption;
pub mod info;
pub mod list;
pub mod open;
pub mod passwd;
pub mod rename;
pub mod resize;
pub mod toggle;
pub mod twofa;
