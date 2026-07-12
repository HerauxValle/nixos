{ lib }:

# The one deliberately-impure step in the whole system, confined to
# exactly this: create a venv, install from a hash-locked requirements
# file inside the FHS sandbox above. Never referenced by execStart as a
# derivation -- only venvDir (a plain path) is, so a broken/stale lock
# can only ever fail this action, never `nixos-rebuild switch` for the
# rest of the system.
{ fhsEnv, venvDir, requirementsLock, extraSteps ? "" }: ''
  ${fhsEnv}/bin/${fhsEnv.name} -c ${lib.escapeShellArg ''
    set -euo pipefail
    rm -rf "${venvDir}"
    python3 -m venv "${venvDir}"
    "${venvDir}/bin/pip" install --require-hashes -r "${requirementsLock}"
    ${extraSteps}
    echo "${builtins.hashFile "sha256" requirementsLock}" > "${venvDir}/.requirements-lock-hash"
  ''}
''
