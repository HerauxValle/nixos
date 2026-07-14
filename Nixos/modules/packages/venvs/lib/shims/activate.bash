# Source this from .bashrc / .zshrc. Not currently used (fish is the
# daily driver -- see lib/shims/activate.fish), shipped for parity since
# venvctl's protocol is shell-agnostic by design and this costs nothing
# to keep working.
#
# Same merge as the fish shim: one command surface. This function
# shadows the real `venvctl` binary on PATH; activate/deactivate are
# handled in-shell (env mutation needs a function, not a subprocess),
# everything else (list, update, help, ...) passes straight through via
# `command venvctl`.

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
      command venvctl deactivate > /dev/null || return 1

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
