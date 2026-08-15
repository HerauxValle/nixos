// &desc: "Module hub for cas's data-driven registries (currently just rootfs distro presets; seccomp presets join later) -- each is a TOML file under data/, parsed at first use, never hand-maintained as Rust literals."
pub mod rootfs;
