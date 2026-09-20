#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROVIDER="${GOAD_PROVIDER_DIR:-}"
readonly LOG_DIR="${GOAD_NOMAD_VALIDATION_LOG_DIR:-/tmp/goad-nomad-runtime-validation-$(date +%Y%m%d-%H%M%S)}"
readonly INVENTORY_DATA="${ROOT}/ad/GOAD/data/inventory"
readonly INVENTORY_PROVIDER="${ROOT}/ad/GOAD/providers/vmware/inventory"
readonly ANSIBLE_CFG="${ROOT}/ansible/ansible.cfg"

readonly WINDOWS_VMS=(GOAD-DC01 GOAD-DC02 GOAD-DC03 GOAD-SRV02 GOAD-SRV03 GOAD-WS01)

declare -A EXPECTED_NAME=(
    [GOAD-DC01]=KINGSLANDING
    [GOAD-DC02]=WINTERFELL
    [GOAD-DC03]=MEEREEN
    [GOAD-SRV02]=CASTELBLACK
    [GOAD-SRV03]=BRAAVOS
    [GOAD-WS01]=WS01
)

declare -A NAT_IP=()

declare -i PASS_COUNT=0
declare -i FAIL_COUNT=0
declare -i WARN_COUNT=0
FINAL_EXERCISE=0

section() {
    echo
    echo "============================================================"
    echo "$*"
    echo "============================================================"
}

pass() {
    PASS_COUNT+=1
    echo "[PASS] $*"
}

warn() {
    WARN_COUNT+=1
    echo "[WARN] $*" >&2
}

fail() {
    FAIL_COUNT+=1
    echo "[FAIL] $*" >&2
    return 1
}

fatal() {
    fail "$*" || true
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fatal "required command not found: $1"
}

vmx_for() {
    local vm="$1"
    local id_file="${PROVIDER}/.vagrant/machines/${vm}/vmware_desktop/id"
    [[ -f "${id_file}" ]] || fatal "missing Vagrant id for ${vm}: ${id_file}"
    local vmx
    vmx="$(cat "${id_file}")"
    [[ -f "${vmx}" ]] || fatal "missing VMX for ${vm}: ${vmx}"
    printf '%s\n' "${vmx}"
}

router_cmd() {
    (
        cd "${PROVIDER}"
        GOAD_PROVIDER_DIR="${PROVIDER}" bash "${ROOT}/scripts/router-ssh.sh" "$1"
    )
}

vagrant_ps() {
    local vm="$1"
    local script encoded
    script="$(cat)"
    encoded="$(printf '%s' "${script}" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)"

    (
        cd "${PROVIDER}"
        timeout 240 vagrant winrm "${vm}" -c \
            "powershell.exe -NoProfile -NonInteractive -EncodedCommand ${encoded}"
    ) 2>&1 | tr -d '\r'
}

find_ansible_playbook() {
    local deploy_root
    deploy_root="$(dirname "$(dirname "$(dirname "${PROVIDER}")")")"

    local -a candidates=(
        "$(command -v ansible-playbook 2>/dev/null || true)"
        "${ROOT}/.venv/bin/ansible-playbook"
        "${ROOT}/venv/bin/ansible-playbook"
        "${deploy_root}/.venv/bin/ansible-playbook"
        "${deploy_root}/venv/bin/ansible-playbook"
        "${HOME}/.goad/.venv/bin/ansible-playbook"
        "${HOME}/.local/bin/ansible-playbook"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        [[ -n "${candidate}" && -x "${candidate}" ]] || continue
        printf '%s\n' "${candidate}"
        return 0
    done

    return 1
}

run_playbook() {
    local playbook="$1"
    local logfile="$2"

    echo "[*] Running ${playbook}"

    (
        cd "${ROOT}/ansible"
        ANSIBLE_CONFIG="${ANSIBLE_CFG}" \
        timeout 3600 "${ANSIBLE_PLAYBOOK}" \
            -i "${INVENTORY_DATA}" \
            -i "${INVENTORY_PROVIDER}" \
            "${playbook}"
    ) 2>&1 | tee "${logfile}"

    if grep -Eq 'failed=[1-9]|unreachable=[1-9]' "${logfile}"; then
        return 1
    fi
}

ansible_ps_north() {
    local host="$1"
    local label="$2"
    local ps_file play_file log_file

    ps_file="${LOG_DIR}/${host}-${label}.ps1"
    play_file="${LOG_DIR}/${host}-${label}.yml"
    log_file="${LOG_DIR}/${host}-${label}.log"

    cat > "${ps_file}"

    python3 - "${host}" "${ps_file}" "${play_file}" <<'PY'
from pathlib import Path
import sys

host = sys.argv[1]
ps = Path(sys.argv[2]).read_text().splitlines()
out = Path(sys.argv[3])
indented = "\n".join("          " + line for line in ps)
out.write_text(
    f"""---
- name: GOAD_NOMAD runtime validation
  hosts: {host}
  gather_facts: false
  tasks:
    - name: Execute validation PowerShell
      ansible.windows.win_powershell:
        script: |
{indented}
      register: validation
    - name: Show validation output
      ansible.builtin.debug:
        var: validation.output
"""
)
PY

    (
        cd "${ROOT}/ansible"
        ANSIBLE_CONFIG="${ANSIBLE_CFG}" \
        timeout 600 "${ANSIBLE_PLAYBOOK}" \
            -i "${INVENTORY_DATA}" \
            -i "${INVENTORY_PROVIDER}" \
            "${play_file}"
    ) 2>&1 | tee "${log_file}"

    ! grep -Eq 'failed=[1-9]|unreachable=[1-9]' "${log_file}"
}

cleanup() {
    local rc=$?
    trap - EXIT INT TERM

    if [[ -n "${PROVIDER}" && -d "${PROVIDER}" && "${FINAL_EXERCISE}" -ne 1 ]]; then
        echo
        echo "[CLEANUP] Returning GOAD_NOMAD to exercise mode..."
        GOAD_PROVIDER_DIR="${PROVIDER}" \
            bash "${ROOT}/scripts/lab-mode.sh" exercise || \
            echo "[CLEANUP] WARNING: automatic exercise-mode recovery failed" >&2
    fi

    # set -e can terminate the validator on an unexpected command error before
    # one of the explicit fatal() paths has a chance to increment FAIL_COUNT.
    # Never print the contradictory FAIL: 0 / [FAILED] combination.
    if [[ "${rc}" -ne 0 && "${FAIL_COUNT}" -eq 0 ]]; then
        FAIL_COUNT=1
        echo "[FAIL] validator aborted on an unexpected command error (rc=${rc}); inspect the last emitted command/log" >&2
    fi

    echo
    echo "============================================================"
    echo "GOAD_NOMAD RUNTIME VALIDATION SUMMARY"
    echo "============================================================"
    echo "PASS: ${PASS_COUNT}"
    echo "WARN: ${WARN_COUNT}"
    echo "FAIL: ${FAIL_COUNT}"
    echo "Logs: ${LOG_DIR}"

    if [[ "${rc}" -eq 0 && "${FAIL_COUNT}" -eq 0 ]]; then
        echo
        echo "[READY] CLEAN-CHECKOUT NETWORK SEGMENTATION RUNTIME VALIDATION PASSED"
        exit 0
    fi

    echo
    echo "[FAILED] NETWORK SEGMENTATION RUNTIME VALIDATION DID NOT PASS"
    exit 1