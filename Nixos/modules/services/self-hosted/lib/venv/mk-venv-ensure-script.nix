# &desc: "Idempotent venv preStart wrapper -- hash-checks requirementsLock marker, skips reinstall if unchanged."

{ lib, mkVenvInstallScript }:

# preStart wrapper -- idempotent, skips the real install unless
# requirementsLock actually changed since the last successful run
# (marker file left by mkVenvInstallScript, compared against
# builtins.hashFile computed at eval time). This is what every
# service's preStart actually calls now; there's no separate manual
# @install action anymore.
{ fhsEnv, venvDir, requirementsLock, extraSteps ? "" }:
let
  lockHash = builtins.hashFile "sha256" requirementsLock;
  marker = "${venvDir}/.requirements-lock-hash";
in
''
  if [ -f "${marker}" ] && [ "$(cat "${marker}" 2>/dev/null)" = "${lockHash}" ]; then
    exit 0
  fi
  ${mkVenvInstallScript { inherit fhsEnv venvDir requirementsLock extraSteps; }}
''
