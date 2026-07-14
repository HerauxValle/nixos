# Shell Integration

`venvctl` needs to modify the current shell environment when activating or
deactivating a virtual environment. Since a child process cannot change its
parent shell's environment, each supported shell ships with a tiny shim that
must be sourced once from your shell's startup file.

---

## Fish

Add the following to `~/.config/fish/config.fish`:

```fish
# Source venvctl shim
set -l venv_shim ~/Dotfiles/Nixos/modules/packages/venvs/lib/shims/activate.fish
test -f $venv_shim; and source $venv_shim
```

---

## Bash

Add the following to `~/.bashrc`:

```bash
# Source venvctl shim
venv_shim=~/Dotfiles/Nixos/modules/packages/venvs/lib/shims/activate.bash
[[ -f "$venv_shim" ]] && source "$venv_shim"
```

---

## Zsh

Add the following to `~/.zshrc`:

```zsh
# Source venvctl shim
venv_shim=~/Dotfiles/Nixos/modules/packages/venvs/lib/shims/activate.zsh
[[ -f "$venv_shim" ]] && source "$venv_shim"
```

---

## POSIX sh

Add the following to your shell's startup file (commonly `~/.profile`):

```sh
# Source venvctl shim
venv_shim="$HOME/Dotfiles/Nixos/modules/packages/venvs/lib/shims/activate.sh"
[ -f "$venv_shim" ] && . "$venv_shim"
```

---

## Nushell

Add the following to your `config.nu`:

```nu
# Source venvctl shim
let venv_shim = $"($env.HOME)/Dotfiles/Nixos/modules/packages/venvs/lib/shims/activate.nu"
if ($venv_shim | path exists) {
    source $venv_shim
}
```

---

## PowerShell

Add the following to your PowerShell profile (for example
`$PROFILE.CurrentUserCurrentHost`):

```powershell
# Source venvctl shim
$venvShim = "$HOME/Dotfiles/Nixos/modules/packages/venvs/lib/shims/activate.ps1"
if (Test-Path $venvShim) {
    . $venvShim
}
```

You can edit your profile with:

```powershell
notepad $PROFILE
```

or create it first if it doesn't exist:

```powershell
if (!(Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force
}
notepad $PROFILE
```

---

After sourcing the appropriate shim (or opening a new shell), `venvctl`
behaves identically in every supported shell:

```text
venvctl activate <venv>
venvctl deactivate
venvctl list
venvctl update
...
```
