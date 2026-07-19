#!/usr/bin/env bash
# &desc: "gitctl dispatcher -- push/release subcommands for config.vars.packages.repos, invoked as `pacnix github <cmd>`."
#
# Expects GITCTL_LIBROOT and everything log.sh/common.sh/push.sh/
# release.sh need already exported by the gitctl wrapper (see
# ../repos.nix).
set -euo pipefail

source "$GITCTL_LIBROOT/log.sh"
source "$GITCTL_LIBROOT/common.sh"

cmd="${1:-help}"
shift || true

case "$cmd" in
  push)
    source "$GITCTL_LIBROOT/push.sh"
    cmd_push "$@"
    ;;
  release)
    source "$GITCTL_LIBROOT/release.sh"
    cmd_release "$@"
    ;;
  -h | --help | help)
    cat << 'EOF'
usage: pacnix github <command> [args]

  push [<name>...]
      Push declared repo(s) per their configured remotes/modes (see
      config.vars.packages.repos). No names = every declared repo.
        e.g. pacnix github push
             pacnix github push dotfiles test

  release <name> <tag> [changelog]
      Squash-push <name>, tag it, push the tag, and (if githubRepo + a
      stored token exist) create a GitHub Release. changelog: omitted =
      generic body, "changelog" = opens $EDITOR, a file path = read
      that file, anything else = used literally.
        e.g. pacnix github release test v1.0.0

  release rm <name> <tag>
      Delete that tag + its GitHub Release (inverse of `release`).
        e.g. pacnix github release rm test v1.0.0
EOF
    ;;
  *)
    log error "unknown command: '$cmd' -- run 'pacnix github help'"
    exit 1
    ;;
esac
