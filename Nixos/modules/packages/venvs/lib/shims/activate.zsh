# &desc: "Zsh environment mutation function that mimics the bash implementation to intercept environment variable configuration calls."

# &desc: "Zsh environment mutation function that mimics the bash implementation to intercept environment variable configuration calls."

# Source this from .zshrc. Functionally identical to the bash shim --
# zsh supports [[ ]], <<<, and local the same way bash does, so this is
# effectively the same code, not a rewrite. Same merged-command-surface
# design as fish/bash/dash/nu: this shadows the real `venvctl` binary on
# PATH with a function of the same name. activate/deactivate mutate env
# in-shell (a subprocess can't do that for its parent); everything else
# (list, update, help, ...) passes straight through via `command venvctl`.

venvctl() {
  if [[ $# -lt 1 ]]; then
    command venvctl
    return $?
  fi

  case "$1" in
    activate)
      if [[ $# -lt 2 ]]; then
        echo "usage: venvctl activate <name|path>" >&2
        return 1
      fi

      local out key val
      out="$(command venvctl activate "$2")" || return 1

      while IFS='=' read -r key val; do
        case "$key" in
          VIRTUAL_ENV) export VIRTUAL_ENV="$val" ;;
          PATH_PREPEND) export VENV_ACTIVE_BIN="$val"; export PATH="$val:$PATH" ;;
        esac
      done <<< "$out"
      ;;
    deactivate)
      command venvctl deactivate "${VIRTUAL_ENV:-}" > /dev/null || return 1

      if [[ -n "${VENV_ACTIVE_BIN:-}" ]]; then
        PATH="$(echo "$PATH" | tr ':' '\n' | grep -vFx "$VENV_ACTIVE_BIN" | paste -sd: -)"
        export PATH
        unset VENV_ACTIVE_BIN
      fi
      unset VIRTUAL_ENV
      ;;
    *)
      # list, update, help, -h/--help, unknown -- let the real binary
      # handle it (including its own error message/exit code for
      # genuinely unknown subcommands).
      command venvctl "$@"
      return $?
      ;;
  esac
}
