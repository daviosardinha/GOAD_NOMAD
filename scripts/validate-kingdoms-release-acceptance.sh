#!/usr/bin/env bash
set -uo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}" || exit 1

readonly INSTANCE="${1:-${INSTANCE:-}}"
if [[ -z "${INSTANCE}" ]]; then
    printf 'Usage: bash scripts/validate-kingdoms-release-acceptance.sh <instance>\n' >&2
    exit 2
fi

readonly PROVIDER="${ROOT}/workspace/${INSTANCE}/provider"
readonly INSTANCE_INVENTORY="${ROOT}/workspace/${INSTANCE}/inventory"
readonly LAB_INVENTORY="${ROOT}/ad/GOAD/data/inventory"
readonly GLOBAL_INVENTORY="${ROOT}/globalsettings.ini"
readonly ANSIBLE_CFG="${ROOT}/ansible/ansible.cfg"
readonly ANSIBLE_PLAYBOOK="${HOME}/.goad/.venv/bin/ansible-playbook"
readonly PYTHON="${HOME}/.goad/.venv/bin/python"
readonly STAMP="$(date +%Y%m%d-%H%M%S)"
readonly EVIDENCE="${KINGDOMS_RELEASE_EVIDENCE:-${HOME}/Kingdoms-evidence/${INSTANCE}-release-acceptance-${STAMP}}"
readonly MASTER_LOG="${EVIDENCE}/acceptance.log"

mkdir -p "${EVIDENCE}"

exec > >(tee -a "${MASTER_LOG}") 2>&1

export GOAD_PROVIDER_DIR="${PROVIDER}"
export KINGDOMS_RDP_INVENTORY="${INSTANCE_INVENTORY}"
export KINGDOMS_RDP_ANSIBLE="${ANSIBLE_PLAYBOOK}"
export PATH="${HOME}/.goad/.venv/bin:${PATH}"

CURRENT_STAGE='startup'

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    return 1
}

restore_exercise() {
    local mode='unknown'
    [[ -f "${PROVIDER}/.goad-nomad-mode" ]] && mode="$(tr -d '[:space:]' < "${PROVIDER}/.goad-nomad-mode")"

    printf '\n[RECOVERY] Current recorded mode: %s\n' "${mode}"
    if [[ "${mode}" != 'exercise' ]]; then
        printf '[RECOVERY] Returning %s to exercise mode after failed/interrupted acceptance.\n' "${INSTANCE}"
        GOAD_PROVIDER_DIR="${PROVIDER}"             bash "${ROOT}/scripts/lab-mode.sh" exercise             2>&1 | tee "${EVIDENCE}/recovery-exercise.log"
        local rc=${PIPESTATUS[0]}
        if [[ ${rc} -ne 0 ]]; then
            printf '[RECOVERY] WARNING: exercise-mode recovery failed with rc=%d\n' "${rc}" >&2
            return "${rc}"
        fi
    fi

    GOAD_PROVIDER_DIR="${PROVIDER}"         bash "${ROOT}/scripts/lab-mode.sh" status         2>&1 | tee "${EVIDENCE}/recovery-status.log" || true
}

on_signal() {
    local signal="$1"
    printf '\n[INTERRUPTED] Signal %s during stage: %s\n' "${signal}" "${CURRENT_STAGE}" >&2
    restore_exercise || true
    printf '[INTERRUPTED] Evidence retained at: %s\n' "${EVIDENCE}" >&2
    exit 130
}

trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

run_stage() {
    local number="$1"
    local name="$2"
    local logfile="$3"
    shift 3

    CURRENT_STAGE="${number} ${name}"
    printf '\n============================================================\n'
    printf 'STAGE %s — %s\n' "${number}" "${name}"
    printf '============================================================\n'

    "$@" 2>&1 | tee "${EVIDENCE}/${logfile}"
    local rc=${PIPESTATUS[0]}

    if [[ ${rc} -ne 0 ]]; then
        printf '\n[FAILED] Stage %s returned rc=%d: %s\n' "${number}" "${rc}" "${name}" >&2
        printf '[FAILED] Stage log: %s/%s\n' "${EVIDENCE}" "${logfile}" >&2
        restore_exercise || true
        printf '[FAILED] Master evidence: %s\n' "${MASTER_LOG}" >&2
        exit "${rc}"
    fi

    printf '[PASS] Stage %s: %s\n' "${number}" "${name}"
}

source_identity() {
    [[ -d "${ROOT}/.git" ]] || { fail 'repository metadata missing'; return 1; }
    [[ -d "${PROVIDER}" ]] || { fail "provider missing: ${PROVIDER}"; return 1; }
    [[ -f "${INSTANCE_INVENTORY}" ]] || { fail "instance inventory missing: ${INSTANCE_INVENTORY}"; return 1; }
    [[ -x "${ANSIBLE_PLAYBOOK}" ]] || { fail "GOAD ansible-playbook missing: ${ANSIBLE_PLAYBOOK}"; return 1; }
    [[ -x "${PYTHON}" ]] || { fail "GOAD Python missing: ${PYTHON}"; return 1; }

    if [[ -n "$(git status --porcelain)" ]]; then
        fail 'working tree is not clean'
        git status --short
        return 1
    fi

    git fetch origin || return 1

    local branch local_head remote_head
    branch="$(git branch --show-current)"
    local_head="$(git rev-parse HEAD)"
    remote_head="$(git rev-parse origin/kingdoms/rdp-access-contract)"

    printf 'Branch      : %s\n' "${branch}"
    printf 'Local HEAD  : %s\n' "${local_head}"
    printf 'Remote HEAD : %s\n' "${remote_head}"
    printf 'Instance    : %s\n' "${INSTANCE}"
    printf 'Provider    : %s\n' "${PROVIDER}"

    [[ "${branch}" == 'kingdoms/rdp-access-contract' ]] || {
        fail "unexpected branch: ${branch}"
        return 1
    }
    [[ "${local_head}" == "${remote_head}" ]] || {
        fail 'local branch does not exactly match origin/kingdoms/rdp-access-contract'
        return 1
    }
}

regression_suite() {
    "${PYTHON}" -m unittest discover -s tests -p 'test_*.py'
}

clean_install_source() {
    bash scripts/validate-goad-kingdoms-install-source.sh
}

rdp_phase01() {
    bash scripts/validate-rdp-runtime.sh --phase01
}

clean_install_runtime() {
    bash scripts/validate-goad-kingdoms-clean-install-runtime.sh
}

full_lpe_runtime() {
    bash scripts/validate-windows-lpe-full-runtime.sh
}

phase02_readiness() {
    INSTANCE="${INSTANCE}"     PROVIDER="${PROVIDER}"     EVIDENCE="${EVIDENCE}/phase02"         bash scripts/validate-phase02-readiness.sh
}

final_health() {
    ANSIBLE_CONFIG="${ANSIBLE_CFG}"     "${ANSIBLE_PLAYBOOK}"         -i "${LAB_INVENTORY}"         -i "${INSTANCE_INVENTORY}"         -i "${GLOBAL_INVENTORY}"         "${ROOT}/ansible/kingdoms-health-final.yml"
}

final_exercise_state() {
    local status
    status="$(GOAD_PROVIDER_DIR="${PROVIDER}" bash scripts/lab-mode.sh status)" || return 1
    printf '%s\n' "${status}"
    grep -Fq 'Recorded mode: exercise' <<<"${status}" || {
        fail 'final recorded mode is not exercise'
        return 1
    }
    grep -Fq 'policy drop;' <<<"${status}" || {
        fail 'final router policy is not deny-by-default'
        return 1
    }
}

vmware_running_set() {
    local output
    output="$(vmrun -T ws list)" || return 1
    printf '%s\n' "${output}"

    mapfile -t running < <(printf '%s\n' "${output}" | tail -n +2 | sed '/^[[:space:]]*$/d')
    [[ ${#running[@]} -eq 7 ]] || {
        fail "expected exactly 7 running Kingdoms VMs, observed ${#running[@]}"
        return 1
    }

    local vm
    for vm in "${running[@]}"; do
        [[ "${vm}" == "${PROVIDER}"/* ]] || {
            fail "unexpected running VM outside ${INSTANCE}: ${vm}"
            return 1
        }
    done
}

printf '\n============================================================\n'
printf 'GOAD KINGDOMS — COMPLETE RELEASE ACCEPTANCE\n'
printf '============================================================\n'
printf 'Instance : %s\n' "${INSTANCE}"
printf 'Evidence : %s\n' "${EVIDENCE}"
printf 'NOTE     : Run via "bash scripts/validate-kingdoms-release-acceptance.sh %s".\n' "${INSTANCE}"
printf '           A validation failure exits this child script, not your interactive shell.\n'

run_stage 0 'Git/source identity' '00-source-identity.log' source_identity
run_stage 1 'Complete Python regression suite' '01-regression-suite.log' regression_suite
run_stage 2 'Clean-install source contract' '02-clean-install-source.log' clean_install_source
run_stage 3 'Read-only RDP + Phase 01 acceptance' '03-rdp-phase01.log' rdp_phase01
run_stage 4 'Complete Kingdoms runtime / segmentation lifecycle' '04-clean-install-runtime.log' clean_install_runtime
run_stage 5 'Full 20-scenario LPE reversibility' '05-lpe-full-runtime.log' full_lpe_runtime
run_stage 6 'Phase 02 pre-lab contract' '06-phase02-readiness.log' phase02_readiness
run_stage 7 'Final domain health proof' '07-final-health.log' final_health
run_stage 8 'Final exercise isolation' '08-final-state.log' final_exercise_state
run_stage 9 'Exclusive VMware running set' '09-vmware-running.log' vmware_running_set

CURRENT_STAGE='complete'

printf '\n============================================================\n'
printf '[READY] %s AUTOMATED RELEASE ACCEPTANCE PASSED\n' "${INSTANCE}"
printf '============================================================\n'
printf 'Evidence: %s\n' "${EVIDENCE}"
printf 'Final state: exercise mode; router deny-by-default; full LPE vulnerable profile restored.\n'
printf '\n'
printf '[MANUAL EVIDENCE STILL REQUIRED]\n'
printf 'Fresh desktop-logon evidence is intentionally not simulated by the current automated validators.\n'
printf 'PR #13 still requires the fresh 15 user/host desktop-login matrix and fresh Robb->CASTELBLACK / Rickon->WS01 session evidence before merge.\n'
