# &desc: "POSIX-compliant shell function shim using variable loop capture to modify environmental variables without subshell side-effects."

# Source this from .profile (or wherever your dash init lives). Same
# merged-command-surface design as the other shims: this shadows the
# real `venvctl` binary on PATH with a shell function of the same name.
# activate/deactivate mutate env in-shell; everything else passes
# straight through via `command venvctl`.
#
# Written in plain POSIX sh -- no [[ ]], no <<<, no process
# substitution, no arrays, since dash has none of these. More
# importantly: this does NOT parse venvctl's output via `| while read`
# the way the bash/zsh shims do, because POSIX sh runs the right-hand
# side of a pipeline in a SUBSHELL -- any `export` set inside that loop
# would be gone the instant the loop exits, silently doing nothing.
# Instead, output is captured into a variable first, then walked with a
# newline-IFS `for` loop, which does not fork a subshell, so the
# exports actually stick in the calling shell. See docs/CAVEATS.md
# "Shim parity is not identical code" for why this one looks different.

venvctl() {
  if [ $# -lt 1 ]; then
    command venvctl
    return $?
  fi

  case "$1" in
    activate)
      if [ $# -lt 2 ]; then
        echo "usage: venvctl activate <name|path>" >&2
        return 1
      fi

      out="$(command venvctl activate "$2")" || return 1

      oldifs="$IFS"
      IFS='
'
      for line in $out; do
        key="${line%%=*}"
        val="${line#*=}"
        case "$key" in
          VIRTUAL_ENV)
            VIRTUAL_ENV="$val"
            export VIRTUAL_ENV
            ;;
          PATH_PREPEND)
            VENV_ACTIVE_BIN="$val"
            export VENV_ACTIVE_BIN
            PATH="$val:$PATH"
            export PATH
            ;;
        esac
      done
      IFS="$oldifs"
      ;;
    deactivate)
      command venvctl deactivate "${VIRTUAL_ENV:-}" > /dev/null || return 1

      if [ -n "${VENV_ACTIVE_BIN:-}" ]; then
        newpath=""
        oldifs="$IFS"
        IFS=':'
        for p in $PATH; do
          if [ "$p" = "$VENV_ACTIVE_BIN" ]; then
            continue
          fi
          if [ -z "$newpath" ]; then
            newpath="$p"
          else
            newpath="$newpath:$p"
          fi
        done
        IFS="$oldifs"
        PATH="$newpath"
        export PATH
        unset VENV_ACTIVE_BIN
      fi
      unset VIRTUAL_ENV
      ;;
    *)
      command venvctl "$@"
      return $?
      ;;
  esac
}
