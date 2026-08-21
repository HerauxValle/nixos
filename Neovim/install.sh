#!/bin/bash

PACMAN_PKGS=(
    neovim
    lazygit
    stylua
    shfmt
    python-black
    clang
)

YAY_PKGS=(
    lazydocker
)

echo "==> Installing pacman packages..."
sudo pacman -S --needed "${PACMAN_PKGS[@]}"

echo "==> Installing yay packages..."
yay -S --needed "${YAY_PKGS[@]}"

echo "✅ Done! Open nvim to let lazy.nvim and Mason install the rest."
