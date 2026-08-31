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

# Build a temporary runtime validator with two compatibility fixes:
# 1. Windows Server exposes conditional-forwarder state through Get-DnsServerZone.
#    There is no Get-DnsServerConditionalForwarderZone cmdlet.
# 2. vagrant_ps must return captured PowerShell/WinRM output even when the remote
#    command exits non-zero, so the validator can print the real error and then
#    fail on its explicit PASS marker instead of silently exiting under set -e.
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

needle = "    ) 2>&1 | tr -d '\\\\r'\n}\n\nfind_ansible_playbook()"
replacement = "    ) 2>&1 | tr -d '\\\\r' || true\n}\n\nfind_ansible_playbook()"

if needle not in s:
    raise SystemExit("Unable to locate vagrant_ps output pipeline in runtime validator")

s = s.replace(needle, replacement, 1)
dst.write_text(s)
PY

bash "${TMP_RUNTIME}" "$@"
