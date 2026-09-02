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

readonly PROVIDER_DIR="${GOAD_PROVIDER_DIR:-}"
[[ -n "${PROVIDER_DIR}" ]] || fail 'GOAD_PROVIDER_DIR is required'
[[ -d "${PROVIDER_DIR}" ]] || fail "GOAD_PROVIDER_DIR does not exist: ${PROVIDER_DIR}"

readonly INSTANCE_DIR="$(dirname "${PROVIDER_DIR}")"
readonly INSTANCE_INVENTORY="${INSTANCE_DIR}/inventory"
readonly LAB_INVENTORY="${ROOT}/ad/GOAD/data/inventory"
readonly GLOBAL_INVENTORY="${ROOT}/globalsettings.ini"
readonly ANSIBLE_PLAYBOOK="${HOME}/.goad/.venv/bin/ansible-playbook"

[[ -x "${ANSIBLE_PLAYBOOK}" ]] || fail "GOAD Ansible runtime missing: ${ANSIBLE_PLAYBOOK}"
[[ -f "${INSTANCE_INVENTORY}" ]] || fail "instance inventory missing: ${INSTANCE_INVENTORY}"
[[ -f "${LAB_INVENTORY}" ]] || fail "lab inventory missing: ${LAB_INVENTORY}"
[[ -f "${GLOBAL_INVENTORY}" ]] || fail "global inventory missing: ${GLOBAL_INVENTORY}"

bash scripts/verify-test-source.sh
pass 'Git source-of-truth gate'

export GOAD_PROVIDER_DIR="${PROVIDER_DIR}"

echo
echo '============================================================'
echo 'GOAD KINGDOMS — UNQUOTED SERVICE PATH RUNTIME PROMOTION GATE'
echo '============================================================'

run_lpe() {
    local action="$1"
    local state="${2:-vulnerable}"

    echo
    echo "=== WINDOWS LPE: ${action^^}${action:+ / ${state^^}} ==="

    local -a args=(
        -i "${LAB_INVENTORY}"
        -i "${INSTANCE_INVENTORY}"
        -i "${GLOBAL_INVENTORY}"
        "${ROOT}/ansible/windows-lpe.yml"
        -e "windows_lpe_action=${action}"
        -e 'windows_lpe_allow_candidate=true'
        -e '{"windows_lpe_techniques":["unquoted_service_path"]}'
    )

    if [[ "${action}" == 'validate' ]]; then
        args+=( -e "windows_lpe_validate_state=${state}" )
    fi

    ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg" \
        "${ANSIBLE_PLAYBOOK}" "${args[@]}"
}

echo
echo '=== 1. CLEAN WS01 BASELINE BEFORE LPE MUTATION ==='
timeout 20m bash scripts/validate-ws01-runtime.sh
pass 'WS01 baseline before LPE mutation'

echo
echo '=== 2. APPLY CANDIDATE ==='
run_lpe apply
pass 'candidate apply + automatic vulnerable-state validation'

echo
echo '=== 3. EXPLICIT VULNERABLE-STATE VALIDATION ==='
run_lpe validate vulnerable
pass 'explicit vulnerable-state validation'

echo
echo '=== 4. RESET CANDIDATE ==='
run_lpe reset
pass 'candidate reset + automatic clean-state validation'

echo
echo '=== 5. EXPLICIT CLEAN-STATE VALIDATION ==='
run_lpe validate clean
pass 'explicit clean-state validation'

echo
echo '=== 6. RE-APPLY CANDIDATE ==='
run_lpe apply
pass 'candidate re-apply + automatic vulnerable-state validation'

echo
echo '=== 7. FINAL VULNERABLE-STATE VALIDATION ==='
run_lpe validate vulnerable
pass 'final vulnerable-state validation'

echo
echo '=== 8. WS01 SECURITY/DOMAIN BASELINE AFTER LPE MUTATION ==='
timeout 20m bash scripts/validate-ws01-runtime.sh
pass 'WS01 baseline remains healthy after candidate re-apply'

echo
echo '============================================================'
echo '[READY] unquoted_service_path live promotion gate passed.'
echo 'Final state: candidate APPLIED / VULNERABLE for training.'
echo '============================================================'
