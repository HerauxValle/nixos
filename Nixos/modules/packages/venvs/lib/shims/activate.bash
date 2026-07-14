# Source this from .bashrc / .zshrc. Not currently used (fish is the
# daily driver -- see lib/shims/activate.fish), shipped for parity since
# venvctl's protocol is shell-agnostic by design and this costs nothing
# to keep working.

venv-activate() {
  if [[ $# -lt 1 ]]; then
    echo "usage: venv-activate <name|path>" >&2
    return 1
  fi

  local out key val
  out="$(venvctl activate "$1")" || return 1

  while IFS='=' read -r key val; do
    case "$key" in
      VIRTUAL_ENV) export VIRTUAL_ENV="$val" ;;
      PATH_PREPEND) export VENV_ACTIVE_BIN="$val"; export PATH="$val:$PATH" ;;
    esac
  done <<< "$out"
}

venv-deactivate() {
  if [[ -n "${VENV_ACTIVE_BIN:-}" ]]; then
    PATH="$(echo "$PATH" | tr ':' '\n' | grep -vFx "$VENV_ACTIVE_BIN" | paste -sd: -)"
    export PATH
    unset VENV_ACTIVE_BIN
  fi
  unset VIRTUAL_ENV
}
