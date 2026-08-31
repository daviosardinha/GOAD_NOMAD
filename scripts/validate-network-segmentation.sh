#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RUNTIME="${ROOT}/scripts/validate-network-segmentation-runtime.sh"
readonly GOAD_VENV="${HOME}/.goad/.venv"

TMP_RUNTIME=""

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

cleanup() {
    if [[ -n "${TMP_RUNTIME}" && -f "${TMP_RUNTIME}" ]]; then
        rm -f "${TMP_RUNTIME}"
    fi
}

trap cleanup EXIT

[[ -f "${RUNTIME}" ]] || fail "runtime validator is missing: ${RUNTIME}"

# GOAD's own goad.sh creates and uses ~/.goad/.venv. A clean source clone does
# not contain that environment, so expose the canonical GOAD runtime before the
# validator performs Ansible discovery.
if ! command -v ansible-playbook >/dev/null 2>&1; then
    if [[ -x "${GOAD_VENV}/bin/ansible-playbook" ]]; then
        export PATH="${GOAD_VENV}/bin:${PATH}"
        echo "[+] Using GOAD Ansible runtime: ${GOAD_VENV}/bin/ansible-playbook"
    else
        fail "ansible-playbook not found. Expected GOAD runtime at ${GOAD_VENV}/bin/ansible-playbook. Run ./goad.sh once to install the GOAD dependencies."
    fi
fi

# Windows Server exposes conditional-forwarder state through Get-DnsServerZone.
# Build a temporary corrected runtime validator so validation still executes
# exclusively from the clean Git checkout without modifying its working tree.
TMP_RUNTIME="$(mktemp /tmp/goad-nomad-runtime.XXXXXX.sh)"

python3 - "${RUNTIME}" "${TMP_RUNTIME}" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
s = src.read_text()

s = s.replace(
    "Get-DnsServerConditionalForwarderZone",
    "Get-DnsServerZone",
)

# Best-effort hardening: preserve WinRM output on a remote PowerShell failure so
# the validator can print the real failure instead of exiting silently under
# set -e. Do not make launcher execution depend on this textual transformation.
s = s.replace(
    ") 2>&1 | tr -d '\\r'\n}",
    ") 2>&1 | tr -d '\\r' || true\n}",
    1,
)

dst.write_text(s)
PY

exec bash "${TMP_RUNTIME}" "$@"
