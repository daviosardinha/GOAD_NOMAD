#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

bash scripts/verify-test-source.sh
pass 'Git source-of-truth gate'

readonly ROLE='ansible/roles/settings/eval_rearm/tasks/main.yml'
readonly PLAYBOOK='ansible/ws01.yml'
readonly RUNTIME='scripts/validate-ws01-runtime.sh'

[[ -f "${ROLE}" ]] || fail "missing ${ROLE}"
[[ -f "${PLAYBOOK}" ]] || fail "missing ${PLAYBOOK}"
[[ -f "${RUNTIME}" ]] || fail "missing ${RUNTIME}"

python3 - <<'PY'
from pathlib import Path


def require(text, token, label):
    if token not in text:
        raise SystemExit(f'{label} missing: {token}')

role = Path('ansible/roles/settings/eval_rearm/tasks/main.yml').read_text()
playbook = Path('ansible/ws01.yml').read_text()
runtime = Path('scripts/validate-ws01-runtime.sh').read_text()

for token in (
    'TIMEBASED_EVAL',
    'GracePeriodRemaining',
    "slmgr.vbs\", '/rearm'",
    'WINDOWS_EVAL=REARMED',
    'WINDOWS_EVAL_READY=PASS',
    'ansible.windows.win_reboot',
):
    require(role, token, 'evaluation rearm role')

require(playbook, "role: 'settings/eval_rearm'", 'WS01 baseline')
require(runtime, 'WS01_EVAL_READY=PASS', 'WS01 runtime validator')
require(runtime, 'TIMEBASED_EVAL', 'WS01 runtime validator')
require(runtime, 'GracePeriodRemaining', 'WS01 runtime validator')

for forbidden in (
    'Set-MpPreference -DisableRealtimeMonitoring',
    'Set-NetFirewallProfile -Enabled False',
    'EnableLUA = 0',
):
    if forbidden.lower() in (role + playbook).lower():
        raise SystemExit(f'evaluation maintenance weakens unrelated security: {forbidden}')
PY
pass 'Mayfly Windows evaluation rearm source contract'

git diff --check
pass 'Git whitespace check'

printf '\n[READY] GOAD Kingdoms WS01 evaluation maintenance source validation passed.\n'
