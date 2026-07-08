#!/usr/bin/env bash
# secrets.sh — dispatcher for the root-owned secrets under /etc/nixos-secrets/.
# Same shape as Pacnix's main.sh: `secrets <command> [args]` runs
# cmd/<command>.sh. The two command names are their own variables below
# (not just filenames) so renaming what you type after `secrets` is a
# one-line edit here, without touching the cmd/ files themselves.
DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

PASSWD_CMD="passwd"
DOTFILES_CMD="dotfiles"

cmd="${1:-help}"
shift || true

case "$cmd" in
    -h | --help) cmd="help" ;;
    "$PASSWD_CMD") cmd="passwd" ;;
    "$DOTFILES_CMD") cmd="dotfiles" ;;
esac

script="$DIR/cmd/${cmd}.sh"
[ ! -f "$script" ] && { echo "unknown command: $cmd" >&2; echo "run 'secrets help' for usage" >&2; exit 1; }
exec bash "$script" "$@"
