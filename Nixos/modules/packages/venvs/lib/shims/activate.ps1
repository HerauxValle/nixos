# &desc: "PowerShell wrapper function for venvctl that captures environment updates to shadow the binary for active session manipulation."

# &desc: "PowerShell wrapper function for venvctl that captures environment updates to shadow the binary for active session manipulation."

# Source this from your PowerShell profile (once). The real `venvctl`
# binary (on PATH) can only print VAR=value lines for
# activate/deactivate -- a child process cannot mutate its parent
# PowerShell session's environment. This function shadows that binary
# with a single PowerShell function of the same name, so there's one
# command surface: `venvctl activate|deactivate` are handled right here
# (parsing the protocol and applying it to *this* session); every other
# subcommand (list, update, help, anything added later) is passed
# straight through to the real binary via `venvctl.exe`. See
# docs/DECISIONS.md "Shim protocol" for why the split exists at all.

function venvctl {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$argv
    )

    if ($argv.Count -lt 1) {
        & venvctl.exe
        return
    }

    switch ($argv[0]) {
        "activate" {
            if ($argv.Count -lt 2) {
                Write-Error "usage: venvctl activate <name|path>"
                return
            }

            $out = & venvctl.exe activate @($argv[1..($argv.Count - 1)])
            if ($LASTEXITCODE -ne 0) {
                return
            }

            foreach ($line in $out) {
                $key, $val = $line -split '=', 2

                switch ($key) {
                    "VIRTUAL_ENV" {
                        $env:VIRTUAL_ENV = $val
                    }
                    "PATH_PREPEND" {
                        $env:VENV_ACTIVE_BIN = $val
                        $env:PATH = "$val$([IO.Path]::PathSeparator)$($env:PATH)"
                    }
                }
            }
        }

        "deactivate" {
            & venvctl.exe deactivate $env:VIRTUAL_ENV | Out-Null
            if ($LASTEXITCODE -ne 0) {
                return
            }

            if ($env:VENV_ACTIVE_BIN) {
                $sep = [IO.Path]::PathSeparator
                $env:PATH = (
                    $env:PATH -split [regex]::Escape($sep) |
                    Where-Object { $_ -ne $env:VENV_ACTIVE_BIN }
                ) -join $sep

                Remove-Item Env:VENV_ACTIVE_BIN
            }

            Remove-Item Env:VIRTUAL_ENV -ErrorAction SilentlyContinue
        }

        default {
            # list, update, help, -h/--help, unknown -- let the real
            # binary handle it (including its own error message/exit
            # code for genuinely unknown subcommands).
            & venvctl.exe @argv
            return
        }
    }
}
