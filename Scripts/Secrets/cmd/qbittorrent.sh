#!/usr/bin/env bash
# secrets qbittorrent -- compute a WebUI login (Username + Password_PBKDF2)
# ready to paste into config/self-hosted/qbittorrent.nix's
# extraServerConfig, straight from a password you type here. Doesn't
# touch qBittorrent at all -- no live conf to read, doesn't need the
# service running, no WebUI round-trip.
#
# Password_PBKDF2's algorithm (PBKDF2-HMAC-SHA512, 100000 iterations, a
# random 16-byte salt, 64-byte derived key, "@ByteArray(<b64 salt>:<b64
# hash>)") isn't qBittorrent's own invention to guess at -- confirmed
# against https://codeberg.org/feathecutie/qbittorrent_password (the
# tool nixpkgs' own services.qbittorrent module doc points at for this
# exact purpose) and cross-checked against this machine's own real prior
# hash: its salt's base64 decodes to exactly 16 bytes, its hash's to
# exactly 64, matching both parameters exactly.
#
# Read-only in the sense that it writes nothing -- unlike every other
# secrets subcommand there's no persistent root-owned file here. Once
# pasted into extraServerConfig it's an ordinary Nix-declared value like
# everything else there, and survives every restart on its own (no
# separate secrets file for anything to read later).
set -euo pipefail

_read_password() {
    local prompt="$1" pass="" char
    printf '%s' "$prompt" >&2
    while IFS= read -r -s -n 1 char; do
        [ -z "$char" ] && break   # Enter
        if [ "$char" = $'\x7f' ]; then   # Backspace
            if [ -n "$pass" ]; then
                pass="${pass%?}"
                printf '\b \b' >&2
            fi
        else
            pass+="$char"
            printf '*' >&2
        fi
    done
    printf '\n' >&2
    printf '%s' "$pass"
}

printf 'Username: ' >&2
read -r username
if [ -z "$username" ]; then
    echo "Username cannot be empty, aborting." >&2
    exit 1
fi

pass1="$(_read_password "Password: ")"
pass2="$(_read_password "Confirm password: ")"

if [ -z "$pass1" ]; then
    echo "Password cannot be empty, aborting." >&2
    exit 1
fi
if [ "$pass1" != "$pass2" ]; then
    echo "Passwords do not match, aborting." >&2
    exit 1
fi

pbkdf2="$(python3 -c '
import sys, os, hashlib, base64
password = sys.stdin.readline().rstrip("\n").encode("utf-8")
salt = os.urandom(16)
derived = hashlib.pbkdf2_hmac("sha512", password, salt, 100000, dklen=64)
print(f"@ByteArray({base64.b64encode(salt).decode()}:{base64.b64encode(derived).decode()})")
' <<< "$pass1")"
unset pass1 pass2

echo ""
echo "Paste into config/self-hosted/qbittorrent.nix's extraServerConfig:"
echo ""
echo "      WebUI = {"
echo "        Username = \"${username}\";"
echo "        Password_PBKDF2 = \"${pbkdf2}\";"
echo "      };"
