#!/usr/bin/env bash
# &desc: "cas-test -- runs whichever of Casket's target/release/cas or target/debug/cas was most recently compiled, for fast local iteration without a full pacnix rebuild. Lives in its own subfolder so wiring it onto PATH doesn't cp -r all of Casket/ (target/ included) into the Nix store."
set -euo pipefail

casketDir="$HOME/Dotfiles/Scripts/Casket"
release="$casketDir/target/release/cas"
debug="$casketDir/target/debug/cas"

newest=""
if [ -x "$release" ] && [ -x "$debug" ]; then
    if [ "$release" -nt "$debug" ]; then
        newest="$release"
    else
        newest="$debug"
    fi
elif [ -x "$release" ]; then
    newest="$release"
elif [ -x "$debug" ]; then
    newest="$debug"
else
    echo "cas-test: no compiled binary found under $casketDir/target/{release,debug}/cas" >&2
    echo "          run 'cargo build' or 'cargo build --release' in $casketDir first" >&2
    exit 1
fi

exec "$newest" "$@"
