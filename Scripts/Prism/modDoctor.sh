#!/usr/bin/env bash
# &desc: "Parses a Prism Launcher instance's latest crash report/log, identifies which installed mod jar threw ClassNotFoundException/NoClassDefFoundError/NoSuchMethodError during entrypoint init, and prints an upgrade/downgrade/remove diagnosis per mod."
set -euo pipefail

INSTANCE="${1:-}"
PRISM_DIR="$HOME/.local/share/PrismLauncher/instances"

if [[ -z "$INSTANCE" ]]; then
    # pick the most recently modified instance if none given
    INSTANCE=$(find "$PRISM_DIR" -maxdepth 1 -mindepth 1 -type d ! -name ".tmp" -printf '%T@ %f\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)
fi

MC_DIR="$PRISM_DIR/$INSTANCE/minecraft"
MODS_DIR="$MC_DIR/mods"
CRASH_DIR="$MC_DIR/crash-reports"

if [[ ! -d "$MODS_DIR" ]]; then
    echo "No such instance/mods dir: $MODS_DIR" >&2
    exit 1
fi

# prefer the newest crash report, fall back to latest.log
SOURCE=$(find "$CRASH_DIR" -maxdepth 1 -name '*.txt' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [[ -z "$SOURCE" ]]; then
    SOURCE="$MC_DIR/logs/latest.log"
fi

if [[ ! -f "$SOURCE" ]]; then
    echo "No crash report or log found for instance '$INSTANCE'." >&2
    exit 1
fi

echo "Instance : $INSTANCE"
echo "Source   : $SOURCE"
echo

# jar-id-cache: modid -> jarpath
declare -A MOD_JAR
for jar in "$MODS_DIR"/*.jar; do
    [[ -f "$jar" ]] || continue
    id=$(unzip -p "$jar" fabric.mod.json 2>/dev/null | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("id",""))
except Exception:
    pass' 2>/dev/null || true)
    [[ -n "$id" ]] && MOD_JAR["$id"]="$jar"
done

jar_version() {
    unzip -p "$1" fabric.mod.json 2>/dev/null | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("version","?"))
except Exception:
    print("?")' 2>/dev/null
}

class_in_jar() {
    # $1 jar, $2 dotted-or-slashed class name
    local cls="${2//.//}"
    unzip -l "$1" 2>/dev/null | grep -q "${cls}\.class"
}

FOUND_ANY=0

# --- Case 1: fabric entrypoint init failure chain ---
# "due to errors, provided by 'CONSUMER' at '...'"
# "Exception while loading entries for entrypoint 'ENTRYPOINT' provided by 'PROVIDER'"
# "ClassNotFoundException: MISSING.CLASS"
while IFS= read -r consumer; do
    FOUND_ANY=1
    entry_line=$(grep -m1 "Exception while loading entries for entrypoint" "$SOURCE" || true)
    entrypoint=$(sed -n "s/.*entrypoint '\([^']*\)' provided by '\([^']*\)'.*/\1/p" <<<"$entry_line")
    provider=$(sed -n "s/.*entrypoint '\([^']*\)' provided by '\([^']*\)'.*/\2/p" <<<"$entry_line")
    missing_class=$(grep -m1 -oE "(ClassNotFoundException|NoClassDefFoundError): [A-Za-z0-9_./]+" "$SOURCE" | head -1 | awk '{print $2}')

    echo "== Entrypoint init failure =="
    echo "Consumer mod : $consumer (requires the '$entrypoint' entrypoint)"
    echo "Provider mod : $provider (declares the broken entrypoint)"

    if [[ -n "${MOD_JAR[$provider]:-}" ]]; then
        jar="${MOD_JAR[$provider]}"
        ver=$(jar_version "$jar")
        echo "Provider jar : $(basename "$jar") (v$ver)"
        if [[ -n "$missing_class" ]] && ! class_in_jar "$jar" "$missing_class"; then
            echo "Missing class: $missing_class (declared in fabric.mod.json but absent from the jar)"
            # look for a same-package class as a rename hint
            pkg_dir=$(dirname "${missing_class//.//}")
            hint=$(unzip -l "$jar" 2>/dev/null | grep -oE "${pkg_dir}/[A-Za-z0-9_$]+\.class" | grep -v "$(basename "${missing_class//.//}").class" | head -3)
            echo
            echo "Diagnosis    : mismatch is INSIDE ${provider}'s own jar -- fabric.mod.json points at a class"
            echo "               that the compiled jar doesn't contain (likely renamed/removed by the author"
            echo "               without updating the manifest). This is a packaging bug in $provider, not a"
            echo "               version clash between $provider and $consumer."
            if [[ -n "$hint" ]]; then
                echo "               Candidate renamed class(es) in the same package:"
                sed 's/^/                 - /' <<<"$hint"
            fi
            echo "Suggested fix: 1) check for a newer $provider build (upstream fix). 2) if none exists, report"
            echo "               it upstream. 3) workaround now: edit ${provider}'s fabric.mod.json to drop or"
            echo "               correct the '$entrypoint' entrypoint entry (disables just that integration)."
        else
            echo
            echo "Diagnosis    : class loads fine in isolation -- likely an API-level mismatch between"
            echo "               $provider and $consumer (method/field removed or changed signature)."
            echo "Suggested fix: update BOTH $provider and $consumer to versions released close together for"
            echo "               this Minecraft/Fabric version; if only one has a newer build, downgrade the"
            echo "               other to match it."
        fi
    else
        echo "Provider jar : not found among installed mods (id '$provider')"
    fi
    echo
done < <(sed -n "s/.*due to errors, provided by '\([^']*\)'.*/\1/p" "$SOURCE")

# --- Case 2: generic NoSuchMethodError / NoSuchFieldError (API mismatch, no entrypoint wrapper) ---
while IFS= read -r line; do
    FOUND_ANY=1
    sig=$(grep -oE "(NoSuchMethodError|NoSuchFieldError): .*" <<<"$line" | head -c 200)
    echo "== API mismatch =="
    echo "$sig"
    echo "Diagnosis    : one mod was compiled against a newer/older API of another mod than what's installed."
    echo "Suggested fix: update the mods involved to versions built for the same Minecraft/Fabric release;"
    echo "               if the log names a specific mod, check its Modrinth/CurseForge page for a build"
    echo "               matching your other mod's version."
    echo
done < <(grep -E "NoSuchMethodError|NoSuchFieldError" "$SOURCE" || true)

if [[ "$FOUND_ANY" -eq 0 ]]; then
    echo "No known mod-incompatibility patterns found in $SOURCE."
fi
