{ ... }:

# The dotfiles-backup module's excludeFiles/redactValues -- no sensible
# generic default (this machine's specific sensitive paths/values), same
# reasoning as config/customized.nix, just split into its own file since
# these two lists are bulkier than a flat scalar. See
# modules/backup/dotfiles/default.nix for what each option actually does.
{
  config.vars.dotfilesBackup = {
    excludeFiles = [
      "Shells/Fish/secrets.fish"
      ".envrc"

      # Local-only variable reference -- reproduces several of the real
      # values redacted/replaced elsewhere (gitCommitEmail, username,
      # usbSerialShort) as plain-text documentation, so publishing it would
      # undo those. Excluding the whole file is simpler and more robust
      # than mirroring every redactValues/replaceValues entry a second
      # time just for a doc, and it doesn't need to be public anyway.
      "Nixos/index.md"

      "**/__pycache__"
      "*.pyc"
      "*.pyo"
      ".mypy_cache"
      ".pytest_cache"
      ".ruff_cache"
      ".venv"
      "venv"
      ".direnv"
      ".DS_Store"

      # Rust build output for the standalone projects under Scripts/
      # (Casket, CRun, ...) -- large, machine-specific, and reproducible
      # from Cargo.lock + flake.lock, so it has no business in the
      # published snapshot.
      "**/target"
    ];
  };
}
