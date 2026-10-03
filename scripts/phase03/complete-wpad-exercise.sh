#!/usr/bin/env bash
# Finalize the Phase 03 mitm6/WPAD exercise.
# Validate the captured chain, then always restore WS01 network state.
# Evidence files are intentionally preserved by the rollback path.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
VALIDATOR="$ROOT/scripts/phase03/validate-wpad-chain.sh"
ROLLBACK="$ROOT/scripts/phase03/rollback-wpad-runtime.sh"

cd "$ROOT" || exit 1

[[ -x "$VALIDATOR" || -f "$VALIDATOR" ]] || {
  echo "FAIL: WPAD validator missing: $VALIDATOR" >&2
  exit 1
}

[[ -x "$ROLLBACK" || -f "$ROLLBACK" ]] || {
  echo "FAIL: WPAD rollback missing: $ROLLBACK" >&2
  exit 1
}

cleanup_attempted=0
cleanup_rc=0

cleanup() {
  local original_rc=$?
  trap - EXIT INT TERM

  if (( cleanup_attempted == 0 )); then
    cleanup_attempted=1
    echo
    echo '===== AUTOMATIC WPAD NETWORK ROLLBACK ====='
    bash "$ROLLBACK"
    cleanup_rc=$?
  fi

  if (( cleanup_rc != 0 )); then
    echo 'FAIL: automatic WPAD rollback did not return WS01 to the captured baseline' >&2
    exit "$cleanup_rc"
  fi

  if (( original_rc != 0 )); then
    echo 'FAIL: WPAD proof failed, but automatic rollback completed successfully' >&2
    exit "$original_rc"
  fi

  echo
  echo 'PHASE03_WPAD_EXERCISE_COMPLETE=True'
  exit 0
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo '===== VALIDATE MITM6 / WPAD EVIDENCE ====='
bash "$VALIDATOR"
