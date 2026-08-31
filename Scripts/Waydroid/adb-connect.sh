#!/usr/bin/env bash
# &desc: "Starts a Waydroid session, unfreezes the container if needed, connects adb, handles the unauthorized-device prompt, and disables Android's screen sleep to stop guest-triggered re-freezing."
set -euo pipefail

echo "[*] Starting Waydroid session..."
waydroid session start &
sleep 6

ip=$(waydroid status | grep "IP address" | sed 's/.*:\s*//' | tr -d '[:space:]')

if waydroid status | grep -q "Container:.*FROZEN"; then
    echo "[!] Container is frozen -- unfreezing..."
    sudo waydroid container unfreeze
    sleep 2
fi

echo "[*] Establishing ADB connection..."
adb start-server
adb connect "$ip:5555"
sleep 3

if adb devices | grep -q "$ip:5555.*unauthorized"; then
    echo "[!] Device unauthorized -- showing Waydroid UI so you can tap 'Always allow'..."
    waydroid show-full-ui &
    echo "[*] Waiting for authorization (accept the prompt on screen)..."
    for _ in $(seq 1 30); do
        sleep 2
        if adb devices | grep -q "$ip:5555.*device$"; then
            echo "[+] Authorized."
            break
        fi
    done
fi

if adb devices | grep -q "$ip:5555.*device$"; then
    echo "[*] Disabling Android screen sleep (prevents guest-triggered re-freeze)..."
    adb -s "$ip:5555" shell svc power stayon true
    adb -s "$ip:5555" shell settings put system screen_off_timeout 2147483647
fi

adb devices -l
