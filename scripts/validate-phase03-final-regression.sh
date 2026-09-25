#!/usr/bin/env bash
# Final regression orchestrator for Kingdoms 03 - Poison the Wells.
# Runs existing read-only/runtime validators and returns the lab to exercise
# mode through the existing segmentation lifecycle validator.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"
INSTANCE="${1:-${INSTANCE:-cebee3-goad-vmware}}"
PROVIDER="${PROVIDER:-$ROOT/workspace/$INSTANCE/provider}"
BRANCH='kingdoms/phase03-overlay'

cd "$ROOT" || exit 1

PASS=0
FAIL=0
CURRENT_STAGE='startup'

pass() {
  PASS=$((PASS+1))
  printf '[PASS] %s\n' "$*"
}

fail() {
  FAIL=$((FAIL+1))
  printf '[FAIL] %s\n' "$*" >&2
}

stage() {
  local name="$1"
  shift

  CURRENT_STAGE="$name"

  printf '\n============================================================\n'
  printf '%s\n' "$name"
  printf '============================================================\n'

  if "$@"; then
    pass "$name"
    return 0
  fi

  fail "$name"
  return 1
}

source_identity() {
  git fetch origin || return 1

  local current local_head remote_head dirty
  current="$(git branch --show-current)"
  local_head="$(git rev-parse HEAD)"
  remote_head="$(git rev-parse "origin/$BRANCH")"

  printf 'Branch      : %s\n' "$current"
  printf 'Local HEAD  : %s\n' "$local_head"
  printf 'Remote HEAD : %s\n' "$remote_head"
  printf 'Instance    : %s\n' "$INSTANCE"
  printf 'Provider    : %s\n' "$PROVIDER"

  [[ "$current" == "$BRANCH" ]] || {
    echo "unexpected branch: $current" >&2
    return 1
  }

  [[ "$local_head" == "$remote_head" ]] || {
    echo 'local branch does not match origin' >&2
    return 1
  }

  [[ -d "$PROVIDER" ]] || {
    echo "provider missing: $PROVIDER" >&2
    return 1
  }

  dirty="$(git status --porcelain)"
  if [[ -n "$dirty" ]]; then
    echo 'working tree is not clean:' >&2
    printf '%s\n' "$dirty" >&2
    return 1
  fi

  echo 'working tree is clean'
  return 0
}

python_regression() {
  python3 -m unittest discover -s tests -p 'test_*.py'
}

phase03_runtime() {
  bash scripts/validate-phase03-runtime.sh
}

phase02_runtime() {
  env \
    INSTANCE="$INSTANCE" \
    PROVIDER="$PROVIDER" \
    bash scripts/validate-phase02-readiness.sh
}

phase01_rdp_runtime() {
  bash scripts/validate-rdp-runtime.sh --phase01 --bot-mode headless
}

segmentation_runtime() {
  GOAD_PROVIDER_DIR="$PROVIDER" \
    bash scripts/validate-network-segmentation-runtime.sh
}

ws01_foundation_runtime() {
  GOAD_PROVIDER_DIR="$PROVIDER" \
    bash scripts/validate-ws01-runtime.sh
}

rickon_runtime() {
  bash scripts/phase03/validate-rickon-session.sh
}

phase03_residual_state() {
  local rc=0

  echo '===== PHASE 03 DIRECTORY / HOST BASELINES ====='

  bash scripts/phase03/check-rbcd-prereqs.sh || rc=1
  bash scripts/phase03/check-shadow-prereqs.sh || rc=1
  bash scripts/phase03/check-adidns-prereqs.sh || rc=1
  bash scripts/phase03/check-webdav-shortcut-prereqs.sh || rc=1

  echo
  echo '===== PHASE 03 NETWORK / CALLBACK RESET ====='

  bash scripts/phase03/verify-wpad-reset.sh || rc=1
  bash scripts/phase03/verify-http-ldaps-callback-clean.sh || rc=1
  bash scripts/phase03/check-http-ldaps-readonly-relay.sh || rc=1

  echo
  echo '===== PHASE 03 LOCAL RUNTIME ====='

  local procs
  procs="$(pgrep -af '(^|[ /])(impacket-ntlmrelayx|ntlmrelayx[.]py|mitm6|Responder[.]py|responder)([ ]|$)' || true)"
  if [[ -n "$procs" ]]; then
    echo 'FAIL: Phase 03 attack process remains active' >&2
    printf '%s\n' "$procs" >&2
    rc=1
  else
    echo 'PASS: no Phase 03 attack process remains'
  fi

  local port
  for port in 80 135 445 1080 5985 5986 6666 9389; do
    if sudo ss -H -lntp "sport = :$port" 2>/dev/null | grep -q .; then
      echo "FAIL: local TCP/$port remains occupied" >&2
      sudo ss -H -lntp "sport = :$port" >&2 || true
      rc=1
    else
      echo "PASS: local TCP/$port is free"
    fi
  done

  return "$rc"
}

echo '============================================================'
echo 'KINGDOMS — PHASE 03 FINAL REGRESSION'
echo '============================================================'
echo "Instance : $INSTANCE"
echo "Provider : $PROVIDER"
echo
echo 'NOTE: the segmentation stage temporarily enters provisioning mode and'
echo 'returns the existing lab to exercise mode through the committed validator.'
echo 'This script is a child process; failure does not terminate your interactive shell.'

stage '0. Git/source identity' source_identity || exit 1
stage '1. Complete Python source regression' python_regression || exit 1
stage '2. Phase 03 runtime/readiness contract' phase03_runtime || exit 1
stage '3. Phase 03 no-residual-state gate (pre-regression)' phase03_residual_state || exit 1
stage '4. Phase 02 readiness/MSSQL regression' phase02_runtime || exit 1
stage '5. Phase 01 + RDP contract regression' phase01_rdp_runtime || exit 1
stage '6. NORTH segmentation lifecycle regression' segmentation_runtime || exit 1
stage '7. WS01 foundation regression after lifecycle' ws01_foundation_runtime || exit 1
stage '8. Rickon permanent session regression after lifecycle' rickon_runtime || exit 1
stage '9. Phase 03 runtime/readiness recheck after lifecycle' phase03_runtime || exit 1
stage '10. Phase 03 no-residual-state gate (final)' phase03_residual_state || exit 1

echo
printf 'PASS: %d\nFAIL: %d\n' "$PASS" "$FAIL"

if (( FAIL == 0 )); then
  echo 'PHASE03_FINAL_REGRESSION_COMPLETE=True'
  exit 0
fi

echo "PHASE03_FINAL_REGRESSION_COMPLETE=False" >&2
exit 1
