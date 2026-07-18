# &desc: "Venv dependencies update builder -- pip-compile diff vs requirementsLock, diff-only or :apply atomic move."
# result against the checked-in requirementsLock. Two modes:
#
# apply = false (the "@update:deps"-style action): print/diff only,
# never overwrites the real lock -- leaves the new one at
# "<requirementsLockPath>.new" if it differs. Predictable, stable path
# (not a mktemp dir that vanishes when the unit exits) so there's
# always something to `mv` into place if you like what you see.
#
# apply = true (the "@update:deps:apply"-style action): same check,
# but if it differs, moves the new lock straight into place instead of
# just printing where it is.
#
# requirementsIn/requirementsLock (Nix paths) are only ever *read* here
# (pip-compile's input, diff's baseline) -- fine as store copies.
# requirementsLockPath is deliberately a plain string, the real
# filesystem path in the actual Dotfiles checkout, not a Nix path --
# ${requirementsLock} would resolve to a read-only /nix/store copy, and
# writing there would be both wrong (not where you'd look for it) and
# impossible (the store is read-only).
{ serviceName, requirementsIn, requirementsLock, requirementsLockPath, apply ? false }: ''
  set -euo pipefail
  new_lock="${requirementsLockPath}.new"
  # Seeding $new_lock with the current real lock before running
  # pip-compile matters: pip-compile only does its normal incremental
  # thing (keep whatever's already pinned unless the new input actually
  # forces a change) when the target output file already exists with
  # prior pins to prefer. Without this, every run re-resolves the whole
  # dependency graph from scratch (confirmed: ~280 packages took
  # 20-40+ minutes for a one-line pin change). Still safe -- this is
  # still a separate file, still never touches the real lock until
  # :apply.
  cp "${requirementsLock}" "$new_lock"
  pip-compile --generate-hashes --allow-unsafe --resolver=backtracking \
    --output-file="$new_lock" "${requirementsIn}" >/dev/null

  if diff -q "${requirementsLock}" "$new_lock" >/dev/null 2>&1; then
    echo "self-hosted-${serviceName}: requirements.lock is already up to date"
    rm -f "$new_lock"
    exit 0
  fi

  echo "self-hosted-${serviceName}: newer requirements available -- package/version diff:"
  diff <(grep -E '^[a-zA-Z0-9_.-]+==' "${requirementsLock}") \
       <(grep -E '^[a-zA-Z0-9_.-]+==' "$new_lock") || true
''
+ (if apply then ''
  mv "$new_lock" "${requirementsLockPath}"
  echo ""
  echo "self-hosted-${serviceName}: applied -- requirements.lock updated. Rebuild + restart to actually use it (preStart's venvEnsureScript picks up the new hash automatically)."
'' else ''
  echo ""
  echo "Full new lock at: $new_lock"
  echo "Apply with: mv \"$new_lock\" \"${requirementsLockPath}\", or just run the :apply variant of this action."
'')
