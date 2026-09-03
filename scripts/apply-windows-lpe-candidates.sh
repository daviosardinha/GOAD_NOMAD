#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

[[ $# -gt 0 ]] || fail 'usage: apply-windows-lpe-candidates.sh <technique> [technique ...]'

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

readonly TECHNIQUES_JSON="$(python3 - "$@" <<'PY'
import json
import sys
print(json.dumps({'windows_lpe_techniques': sys.argv[1:]}))
PY
)"

printf '\n=== APPLY WINDOWS LPE CANDIDATES ===\n'
printf 'Techniques: %s\n' "$*"

ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg" \
    "${ANSIBLE_PLAYBOOK}" \
    -i "${LAB_INVENTORY}" \
    -i "${INSTANCE_INVENTORY}" \
    -i "${GLOBAL_INVENTORY}" \
    "${ROOT}/ansible/windows-lpe.yml" \
    -e 'windows_lpe_action=apply' \
    -e 'windows_lpe_allow_candidate=true' \
    -e "${TECHNIQUES_JSON}"

printf '\n[READY] Selected Windows LPE candidates are applied and vulnerable-state validation passed.\n'
printf 'Existing unselected LPE scenarios were not reset.\n'
