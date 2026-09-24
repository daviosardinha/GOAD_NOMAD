#!/usr/bin/env bash
# Phase 03 runtime validation orchestrator.
# Current checkpoint validates baseline + source/guard contracts only.
set -uo pipefail

ROOT="${ROOT:-$HOME/Documents/GOAD_NOMAD}"

cd "$ROOT" || exit 1

PASS=0
FAIL=0

pass(){ PASS=$((PASS+1)); printf '[PASS] %s\n' "$*"; }
fail(){ FAIL=$((FAIL+1)); printf '[FAIL] %s\n' "$*" >&2; }

echo '============================================================'
echo 'KINGDOMS — 03 POISON THE WELLS — RUNTIME CONTRACT'
echo '============================================================'

if bash scripts/validate-phase03-readiness.sh; then
  pass 'Phase 03 readiness baseline'
else
  fail 'Phase 03 readiness baseline'
fi

echo
echo '===== SOURCE CONTRACT ====='
if python3 -m unittest \
    tests.test_phase03_overlay_source \
    tests.test_phase03_rickon_headless; then
  pass 'Phase 03 overlay + Rickon victim source contracts'
else
  fail 'Phase 03 overlay + Rickon victim source contracts'
fi

echo
echo '===== REQUIRED FILES ====='
for path in   ansible/phase03.yml   scripts/apply-phase03.sh   scripts/validate-phase03-runtime.sh   scripts/reset-phase03.sh   docs/kingdoms-phase03-runtime-checkpoint.md
do
  if [[ -f "$path" ]]; then
    pass "$path"
  else
    fail "missing $path"
  fi
done

echo
printf 'PASS: %d\nFAIL: %d\n' "$PASS" "$FAIL"

(( FAIL == 0 ))
