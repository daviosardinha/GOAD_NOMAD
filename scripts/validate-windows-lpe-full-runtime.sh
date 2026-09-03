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
readonly FULL_JSON='{"windows_lpe_techniques":["unquoted_service_path","weak_service_dacl","weak_service_binary_permissions","weak_service_registry_permissions","service_dll_hijacking","path_search_order_hijacking","always_install_elevated","registry_run_keys","writable_startup_folder","scheduled_task_binary_permissions","scheduled_task_directory_permissions","unattend_credentials","powershell_history_credentials","hardcoded_application_credentials","stored_runas_credentials","stored_winlogon_credentials","sebackup_privilege","seimpersonate_privilege","writable_program_directory","insecure_service_registry"]}'

[[ -x "${ANSIBLE_PLAYBOOK}" ]] || fail "GOAD Ansible runtime missing: ${ANSIBLE_PLAYBOOK}"
[[ -f "${INSTANCE_INVENTORY}" ]] || fail "instance inventory missing: ${INSTANCE_INVENTORY}"
[[ -f "${LAB_INVENTORY}" ]] || fail "lab inventory missing: ${LAB_INVENTORY}"
[[ -f "${GLOBAL_INVENTORY}" ]] || fail "global inventory missing: ${GLOBAL_INVENTORY}"
[[ -f "${WS01_ID_FILE}" ]] || fail "WS01 VMware id file missing: ${WS01_ID_FILE}"
command -v vmrun >/dev/null 2>&1 || fail 'vmrun is required'
command -v nc >/dev/null 2>&1 || fail 'nc is required'

readonly WS01_VMX="$(cat "${WS01_ID_FILE}")"
readonly WS01_LOG="$(dirname "${WS01_VMX}")/vmware.log"

ws01_running() {
    vmrun -T ws list 2>/dev/null | grep -Fxq "${WS01_VMX}"
}

dump_ws01_evidence() {
    echo
    echo '=== WS01 FAILURE EVIDENCE ==='
    (cd "${PROVIDER_DIR}" && vagrant status GOAD-WS01) 2>/dev/null || true
    vmrun -T ws list 2>/dev/null || true
    echo '--- recent VMware power events ---'
    grep -Ei 'softPowerOff|power.?off|shutdown|panic|crash|VMX exit|cleanShutdown' "${WS01_LOG}" 2>/dev/null | tail -n 60 || true
}

require_ws01_ready() {
    local phase="$1"
    local deadline=$((SECONDS + READY_TIMEOUT))

    ws01_running || {
        dump_ws01_evidence
        fail "WS01 powered off before/after phase: ${phase}"
    }

    while (( SECONDS < deadline )); do
        if nc -z -w 3 10.4.10.31 5986 >/dev/null 2>&1; then
            pass "WS01 power + WinRM healthy (${phase})"
            return 0
        fi
        sleep 5
    done

    dump_ws01_evidence
    fail "WS01 WinRM TCP/5986 unavailable after ${READY_TIMEOUT}s (${phase})"
}

on_error() {
    local rc=$?
    dump_ws01_evidence
    exit "${rc}"
}
trap on_error ERR

run_full() {
    local action="$1"
    local state="${2:-vulnerable}"

    require_ws01_ready "before ${action}/${state}"
    echo
    echo "=== FULL 20 LPE: ${action^^}${action:+ / ${state^^}} ==="

    local -a args=(
        -i "${LAB_INVENTORY}"
        -i "${INSTANCE_INVENTORY}"
        -i "${GLOBAL_INVENTORY}"
        "${ROOT}/ansible/windows-lpe.yml"
        -e "windows_lpe_action=${action}"
        -e "${FULL_JSON}"
    )
    if [[ "${action}" == 'validate' ]]; then
        args+=( -e "windows_lpe_validate_state=${state}" )
    fi

    ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg" \
        "${ANSIBLE_PLAYBOOK}" "${args[@]}"

    require_ws01_ready "after ${action}/${state}"
}

echo
echo '============================================================'
echo 'GOAD KINGDOMS — WINDOWS LPE FULL 20-SCENARIO RUNTIME GATE'
echo '============================================================'

echo
echo '=== 0. SOURCE GATE ==='
bash scripts/validate-windows-lpe-framework-source.sh
pass 'Windows LPE source gate'

echo
echo '=== 1. WS01 SECURITY/DOMAIN BASELINE WITH ALL 20 LIVE ==='
timeout 20m bash scripts/validate-ws01-runtime.sh
require_ws01_ready 'baseline-before'
pass 'WS01 baseline healthy with all 20 scenarios live'

echo
echo '=== 2. EXPLICIT VULNERABLE-STATE VALIDATION OF ALL 20 ==='
run_full validate vulnerable
pass 'all 20 scenarios explicitly validate vulnerable'

echo
echo '=== 3. RESET ALL 20 ==='
run_full reset
pass 'all 20 scenarios reset and automatic clean validation passed'

echo
echo '=== 4. EXPLICIT CLEAN-STATE VALIDATION OF ALL 20 ==='
run_full validate clean
pass 'all 20 scenarios explicitly validate clean'

echo
echo '=== 5. RE-APPLY ALL 20 TOGETHER ==='
run_full apply
pass 'all 20 scenarios re-applied and automatic vulnerable validation passed'

echo
echo '=== 6. FINAL EXPLICIT VULNERABLE-STATE VALIDATION ==='
run_full validate vulnerable
pass 'all 20 scenarios final vulnerable validation passed'

echo
echo '=== 7. WS01 SECURITY/DOMAIN BASELINE AFTER FULL REVERSIBILITY CYCLE ==='
timeout 20m bash scripts/validate-ws01-runtime.sh
require_ws01_ready 'baseline-after'
pass 'WS01 baseline remains healthy after full 20-scenario cycle'

echo
echo '============================================================'
echo '[READY] Windows LPE full 20-scenario reversible runtime gate passed.'
echo 'Final state: 20 implemented techniques APPLIED / VULNERABLE for training.'
echo '============================================================'
