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

resolve_provider() {
    if [[ -n "${GOAD_PROVIDER_DIR:-}" ]]; then
        [[ -d "${GOAD_PROVIDER_DIR}" ]] || fail "GOAD_PROVIDER_DIR does not exist: ${GOAD_PROVIDER_DIR}"
        PROVIDER_DIR="${GOAD_PROVIDER_DIR}"
        return
    fi

    local -a ids=()
    mapfile -t ids < <(
        find "${ROOT}/workspace" \
            -type f \
            -path '*/provider/.vagrant/machines/GOAD-WS01/vmware_desktop/id' \
            -print 2>/dev/null
    )
    [[ ${#ids[@]} -eq 1 ]] || fail 'set GOAD_PROVIDER_DIR to the deployed GOAD/VMware provider directory'
    PROVIDER_DIR="${ids[0]%%/.vagrant/*}"
}

resolve_provider
export GOAD_PROVIDER_DIR="${PROVIDER_DIR}"

readonly INSTANCE_DIR="$(dirname "${PROVIDER_DIR}")"
readonly INSTANCE_INVENTORY="${INSTANCE_DIR}/inventory"
readonly LAB_INVENTORY="${ROOT}/ad/GOAD/data/inventory"
readonly GLOBAL_INVENTORY="${ROOT}/globalsettings.ini"
readonly ANSIBLE_PLAYBOOK="${HOME}/.goad/.venv/bin/ansible-playbook"
readonly WS01_ID_FILE="${PROVIDER_DIR}/.vagrant/machines/GOAD-WS01/vmware_desktop/id"
readonly READY_TIMEOUT="${GOAD_KINGDOMS_LPE_READY_TIMEOUT:-300}"

[[ -x "${ANSIBLE_PLAYBOOK}" ]] || fail "GOAD Ansible runtime missing: ${ANSIBLE_PLAYBOOK}"
[[ -f "${INSTANCE_INVENTORY}" ]] || fail "instance inventory missing: ${INSTANCE_INVENTORY}"
[[ -f "${LAB_INVENTORY}" ]] || fail "lab inventory missing: ${LAB_INVENTORY}"
[[ -f "${GLOBAL_INVENTORY}" ]] || fail "global inventory missing: ${GLOBAL_INVENTORY}"
[[ -f "${WS01_ID_FILE}" ]] || fail "WS01 VMware id file missing: ${WS01_ID_FILE}"
command -v vmrun >/dev/null 2>&1 || fail 'vmrun is required'
command -v nc >/dev/null 2>&1 || fail 'nc is required'

readonly WS01_VMX="$(cat "${WS01_ID_FILE}")"

ws01_running() {
    vmrun -T ws list 2>/dev/null | grep -Fxq "${WS01_VMX}"
}

require_ws01_ready() {
    local phase="$1"
    local deadline=$((SECONDS + READY_TIMEOUT))

    ws01_running || fail "WS01 is not running (${phase})"

    while (( SECONDS < deadline )); do
        if nc -z -w 3 10.4.10.31 5986 >/dev/null 2>&1; then
            pass "WS01 power + WinRM healthy (${phase})"
            return 0
        fi
        sleep 5
    done

    fail "WS01 WinRM TCP/5986 unavailable after ${READY_TIMEOUT}s (${phase})"
}

echo
echo '============================================================'
echo 'GOAD KINGDOMS — WINDOWS LPE PROMOTED PROFILE ACCEPTANCE GATE'
echo '============================================================'

echo
echo '=== 1. SOURCE CONTRACT ==='
bash scripts/validate-windows-lpe-framework-source.sh
pass 'promoted 20-technique source contract'

echo
echo '=== 2. WS01 BASELINE ==='
timeout 20m bash scripts/validate-ws01-runtime.sh
require_ws01_ready 'baseline'
pass 'WS01 baseline healthy before promoted-profile validation'

echo
echo '=== 3. FULL-LPE PROFILE WITHOUT CANDIDATE OPT-IN ==='
ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg" \
    "${ANSIBLE_PLAYBOOK}" \
    -i "${LAB_INVENTORY}" \
    -i "${INSTANCE_INVENTORY}" \
    -i "${GLOBAL_INVENTORY}" \
    "${ROOT}/ansible/windows-lpe.yml" \
    -e 'windows_lpe_action=validate' \
    -e 'windows_lpe_profile=full-lpe' \
    -e 'windows_lpe_validate_state=vulnerable'
require_ws01_ready 'full-lpe validate/vulnerable'
pass 'full-lpe profile validates all 20 vulnerable without candidate opt-in'

echo
echo '============================================================'
echo '[READY] Windows LPE promoted 20-technique profile acceptance gate passed.'
echo 'Final state unchanged: 20 implemented techniques APPLIED / VULNERABLE.'
echo '============================================================'
