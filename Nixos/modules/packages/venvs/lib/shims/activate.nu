# &desc: "Nushell wrapper definition opting into environment mutation via def --env to intercept and update active environment variables."

# &desc: "Nushell wrapper definition opting into environment mutation via def --env to intercept and update active environment variables."

# Source this from config.nu (once). Nu doesn't let a plain `def` leak
# $env changes back to the caller -- `def --env` opts in, which is nu's
# version of the same subprocess-can't-mutate-parent problem every
# other shim here works around differently (fish/bash/zsh/dash source a
# function; nu just needs the keyword). Everything but
# activate/deactivate is a plain passthrough to the real binary via
# `^venvctl` (the `^` forces the external command, bypassing this very
# definition, same role as `command venvctl` in the other shims).
#
# Targets nu 0.90+-era syntax (`match`, `complete`, `hide-env`). Nu's
# scripting surface moves faster than bash/zsh/dash/fish's -- if your
# installed version is older, some of this may need adjusting. See
# docs/CAVEATS.md.

def --env venvctl [...args] {
  if ($args | length) == 0 {
    ^venvctl
    return
  }

  match ($args | get 0) {
    "activate" => {
      if ($args | length) < 2 {
        print -e "usage: venvctl activate <name|path>"
        return
      }

      let result = (^venvctl activate ($args | get 1) | complete)
      if $result.exit_code != 0 {
        print -e $result.stderr
        return
      }

      for line in ($result.stdout | lines) {
        let parts = ($line | split row "=")
        let key = ($parts | get 0)
        let val = ($parts | get 1)

        if $key == "VIRTUAL_ENV" {
          $env.VIRTUAL_ENV = $val
        } else if $key == "PATH_PREPEND" {
          $env.VENV_ACTIVE_BIN = $val
          $env.PATH = ($env.PATH | prepend $val)
        }
      }
    }
    "deactivate" => {
      let active = ($env.VIRTUAL_ENV? | default "")
      ^venvctl deactivate $active | complete | ignore

      if "VENV_ACTIVE_BIN" in $env {
        let removed = $env.VENV_ACTIVE_BIN
        $env.PATH = ($env.PATH | where {|p| $p != $removed})
        hide-env VENV_ACTIVE_BIN
      }
      hide-env VIRTUAL_ENV
    }
    _ => {
      ^venvctl ...$args
    }
  }
}
