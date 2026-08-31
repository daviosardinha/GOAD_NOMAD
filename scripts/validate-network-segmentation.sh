#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RUNTIME="${ROOT}/scripts/validate-network-segmentation-runtime.sh"
readonly GOAD_VENV="${HOME}/.goad/.venv"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

[[ -f "${RUNTIME}" ]] || fail "runtime validator is missing: ${RUNTIME}"

# GOAD's own goad.sh creates and uses ~/.goad/.venv. A clean source clone does
# not contain that environment, so make the canonical existing GOAD runtime
# available to the validator before it attempts Ansible discovery.
if ! command -v ansible-playbook >/dev/null 2>&1; then
    if [[ -x "${GOAD_VENV}/bin/ansible-playbook" ]]; then
        export PATH="${GOAD_VENV}/bin:${PATH}"
        echo "[+] Using GOAD Ansible runtime: ${GOAD_VENV}/bin/ansible-playbook"
    else
        fail "ansible-playbook not found. Expected GOAD runtime at ${GOAD_VENV}/bin/ansible-playbook. Run ./goad.sh once to install the GOAD dependencies."
    fi
fi

exec bash "${RUNTIME}" "$@"
