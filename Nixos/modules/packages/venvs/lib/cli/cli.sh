#!/usr/bin/env bash
# This is what `venvctl` execs into (see venv.nix). Kept intentionally
# dumb -- all it does is route to a microscript per subcommand. Each
# subcommand script is independently sourceable/testable.
set -euo pipefail

: "${VENVCTL_LIBROOT:?VENVCTL_LIBROOT not set}"
: "${VENVCTL_DATA:?VENVCTL_DATA not set}"

usage() {
  cat <<'EOF'
venvctl <command> [args]

Commands:
  activate <name|path>   Print the neutral env protocol for a venv
                          (see docs/DECISIONS.md "Shim protocol").
                          Not meant to be run bare -- source it via the
                          fish/bash shim in lib/shims/.
  deactivate              Print the neutral protocol to unset the
                          currently active venv (same caveat as above).
  list                    List all declared venvs and their state.
  update <name|all>       Bump floating ("latest") packages only.
EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
  activate)
    [[ $# -ge 1 ]] || { echo "usage: venvctl activate <name|path>" >&2; exit 1; }
    bash "$VENVCTL_LIBROOT/cli/activate.sh" "$1"
    ;;
  deactivate)
    bash "$VENVCTL_LIBROOT/cli/deactivate.sh"
    ;;
  list)
    bash "$VENVCTL_LIBROOT/cli/list.sh"
    ;;
  update)
    [[ $# -ge 1 ]] || { echo "usage: venvctl update <name|all>" >&2; exit 1; }
    bash "$VENVCTL_LIBROOT/manage/update.sh" "$1"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "venvctl: unknown command '$cmd'" >&2
    usage >&2
    exit 1
    ;;
esac
