#!/usr/bin/env bash
# No venv data needed -- deactivation just unsets VIRTUAL_ENV and asks
# the shim to strip whatever bin dir IT remembers prepending. The empty
# value is the sentinel shims key off; see docs/DECISIONS.md.
set -euo pipefail

echo "VIRTUAL_ENV="
