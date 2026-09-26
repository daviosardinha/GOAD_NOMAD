#!/usr/bin/env bash
# Permanent Phase 03 reset entrypoint.
# Current checkpoint has no state-changing Phase 03 fixtures to undo.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"

cd "$ROOT" || exit 1

[[ "${1:-}" == "--confirm" ]] || {
  cat <<'EOF'
Usage:
  bash scripts/reset-phase03.sh --confirm

No state-changing Phase 03 fixture exists in the current checkpoint.
This command verifies the neutral readiness baseline only.
EOF
  exit 2
}

if [[ -n "$(git status --porcelain)" ]]; then
  echo "FAIL: working tree must be clean before Phase 03 reset validation" >&2
  git status --short >&2
  exit 1
fi

echo "INFO: no permanent Phase 03 state-changing fixture is currently installed."
echo "INFO: validating neutral baseline..."

bash scripts/validate-phase03-readiness.sh
rc=$?

if [[ $rc -eq 0 ]]; then
  echo "PASS: Phase 03 neutral baseline is healthy."
fi

exit "$rc"
