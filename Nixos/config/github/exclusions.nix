{ ... }:

# The dotfiles-backup module's excludeFiles/redactValues -- no sensible
# generic default (this machine's specific sensitive paths/values), same
# reasoning as config/config.nix, just split into its own file since
# these two lists are bulkier than a flat scalar. See
# modules/backup/dotfiles/default.nix for what each option actually does.
{
  config.vars.backup.dotfilesBackup = {
    excludeFiles = [
      "Shells/Fish/secrets.fish"
      ".envrc"

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
