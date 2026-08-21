#!/usr/bin/env bash
# &desc: "mcli entrypoint -- dispatches to cmd/<name>.sh, same main.sh/cmd//lib pattern as Pacnix."
DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
cmd="${1:-help}"
case "$cmd" in
    -h | --help) cmd="help" ;;
esac
shift || true
script="$DIR/cmd/${cmd}.sh"
[ ! -f "$script" ] && { echo "unknown command: $cmd" >&2; echo "run 'mcli help' for usage" >&2; exit 1; }
exec bash "$script" "$@"
