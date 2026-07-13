# GENERAL

alias sudo='sudo '
alias hi='echo "Hello from Fish!"'                                      #&help:"Prints "Hello from Fish!""
alias timeshift-gui="sudo GDK_BACKEND=x11 timeshift-gtk"                #&help:"Opens Timeshift GUI"
alias grubreload="sudo grub-mkconfig -o /boot/grub/grub.cfg"            #&help:"Reloads grub config"
alias rebuild="pacnix rebuild 2>&1 | tee /tmp/pacnix-rebuild.log"       #&help:"Rebuilds nixos with pacnix"
# NIXOS (see pacnix -- Scripts/Pacnix -- for rebuild/validate/check/test-build)

# UTILITIES
alias pit="~/Scripts/Shell/Bash/pakeit.sh"                              #&help:"Create a webapp from a URL"
alias idr="sudo ~/Scripts/Shell/Bash/davinciResolve.sh"                 #&help:"Launch DaVinci Resolve"
alias gpa="python3 ~/Scripts/Python/gitpushall.py"                      #&help:"Push dotfiles to all git remotes"
alias lwp="nohup bash ~/Scripts/Shell/Bash/wallpaper.sh > /dev/null 2>&1 &" #&help:"Cycle wallpaper"
alias fsu="python3 ~/Scripts/Python/fixsudo.py"                         #&help:"Fix sudo permissions"
alias cln="~/Scripts/Python/countlines.py"                              #&help:"Count lines in files/dirs"
alias pyc="python3 ~/Scripts/Python/pycache.py"                         #&help:"Clean Python __pycache__"
alias exc="python3 ~/Scripts/Python/exec.py"                            #&help:"Bulk-set executable permissions"
alias vlt="cd ~/Images && printf %s "314159265" | cas Vaults toggle --pass 314159265 --keyfile /run/media/herauxvalle/VirtualKeys/vaults/vaults.key --no-log" #&help:"Toggle Vaults LUKS container"
alias fwm="~/Projects/FloatingWM/main.sh"                               #&help:"Launch FloatingWM"
alias doc="man"                                                          #&help:"Alias for man pages"
alias backup="~/Dotfiles/Scripts/Backup/backup.sh"                      #&help:"Snapshot/restore live config not managed by Nix (--restore to restore)"
alias ytv="mpv --ytdl-format='bestvideo[height<=1080]+bestaudio/best'"  #&help:"Play a URL in mpv at best 1080p video+audio"

# SERVICES

alias shared="/home/herauxvalle/Scripts/Python/Shared/main.py"          #&help:"Easily share files"

alias jellyfin="~/Scripts/Self-hosted/Jellyfin/main.sh"                 #&help:"Launch JellyFin service"
alias qbittorrent="~/Scripts/Self-hosted/QBitTorrent/main.sh"           #&help:"Launch QBitTorrent service"
alias obsidian="~/Scripts/Shell/Menu/obsidian.sh"                       #&help:"Launch Obsidian AppImage"
alias onitor="~/Scripts/Self-hosted/Tor/Browser/main.sh"                #&help:"Launch Tor Browser"
alias onixng="~/Scripts/Self-hosted/Tor/MCP/torch.sh"                   #&help:"Launch Tor MCP proxy"
alias stash="~/Scripts/Self-hosted/Stash/main.sh"                       #&help:"Manage Stash media server"
alias searxng="~/Scripts/Self-hosted/SearXNG/main.sh"                   #&help:"Manage SearXNG service"
alias comfyui="~/Scripts/Self-hosted/ComfyUI/main.sh"                   #&help:"Manage ComfyUI service"
alias owui="~/Scripts/Self-hosted/OpenWebUI/main.sh"                    #&help:"Manage OpenWebUI service"
alias ollama="~/Scripts/Self-hosted/Ollama/main.sh"                     #&help:"Manage Ollama service"
alias immich="~/Scripts/Self-hosted/Immich/main.sh"                     #&help:"Manage Immich service"
alias odysseus="~/Scripts/Self-hosted/Odysseus/main.sh"                 #&help:"Manage Odysseus service"
alias modules="~/Scripts/Self-hosted/General/scripts/main.sh --module"  #&help:"Run self-hosted module scripts"
alias startall="comfyui --restart --no-debug && owui --restart --no-debug && ollama --restart --no-debug" #&help:"Restart ComfyUI + OpenWebUI + Ollama"

# KEEPASSXC

alias kdbx="~/Scripts/Shell/Menu/kbdx.sh"                               #&help:"KeePassXC menu script"
alias kdbx-open="nohup keepassxc /run/media/herauxvalle/VirtualKeys/keepassxc/passwords.kdbx &>/dev/null & disown" #&help:"Open KeePassXC GUI"
alias kbdx-cli="keepassxc-cli open /run/media/herauxvalle/VirtualKeys/keepassxc/passwords.kdbx" #&help:"Open KeePassXC in CLI"

# APPLICATIONS

alias celshell="pkill qs; qs -c ~/Projects/Caelestia &"                  #&help:"Restart QS with Caelestia config"
alias modrinth="~/Scripts/Shell/Vaults/modrinth.sh"                     #&help:"Open Modrinth vault"

# PACMAN AND YAY

# r = Remove (uninstall)
# n = Remove config files (not just the package)
# s = Remove dependencies that aren't needed by other packages
# c = Remove cascade - also remove packages that depend on this one

alias ys="yay -S"                                                       #&help:"Installs yay pkgs"
alias yrnc="yay -Rnsc"                                                 #&help:"Uninstalls yay pkgs (cascade)"
alias yrns="yay -Rns"                                                   #&help:"Uninstalls yay pkgs (safe)"
alias yss="yay -Ss"                                                     #&help:"Searches yay pkgs"

alias s="sudo pacman -S"                                                #&help:"Installs pacman pkgs"
alias rnc="sudo pacman -Rnsc"                                          #&help:"Uninstalls pacman pkgs (cascade)"
alias rns="sudo pacman -Rns"                                            #&help:"Uninstalls pacman pkgs (safe)"
alias ss="sudo pacman -Ss"                                              #&help:"Searches pacman pkgs"

# NAVIGATION
alias back="cd .."                                                      #&help:"Go to parent dir"
alias home="cd ~"                                                       #&help:"Go to $HOME"
alias ls="eza"                                                          #&help:"List dir contents (colorized eza)"
alias lsa="eza -la --group-directories-first --color=always"            #&help:"List dir contents, alphabetical, colored type/perms"
alias lsr="eza -1 --color=always"                                       #&help:"List dir contents, alphabetical, one per line, colored"

# CUSTOM SUDO
alias approve="sudo --adv:approve"                                       #&help:"Approve latest sudo broker request"
alias deny="sudo --adv:deny"                                             #&help:"Deny latest sudo broker request"
alias session="sudo --adv:auto-session-no-warning"                       #&help:"Enable sudo auto-session for this terminal"
