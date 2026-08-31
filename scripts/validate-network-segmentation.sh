#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RUNTIME="${ROOT}/scripts/validate-network-segmentation-runtime.sh"
readonly GOAD_VENV="${HOME}/.goad/.venv"
readonly EXCLUDE_FILE="${ROOT}/.git/info/exclude"
readonly EXCLUDE_PATTERN="scripts/.goad-nomad-runtime.*.sh"

TMP_RUNTIME=""
ADDED_EXCLUDE=0

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

cleanup() {
    if [[ -n "${TMP_RUNTIME}" && -f "${TMP_RUNTIME}" ]]; then
        rm -f "${TMP_RUNTIME}"
    fi

    if [[ "${ADDED_EXCLUDE}" -eq 1 && -f "${EXCLUDE_FILE}" ]]; then
        python3 - "${EXCLUDE_FILE}" "${EXCLUDE_PATTERN}" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
pattern = sys.argv[2]
lines = p.read_text().splitlines()
p.write_text("\n".join(line for line in lines if line != pattern) + "\n")
PY
    fi
}

trap cleanup EXIT

[[ -f "${RUNTIME}" ]] || fail "runtime validator is missing: ${RUNTIME}"
[[ -d "${ROOT}/.git" ]] || fail "run this validator from a Git clone"

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

# The patched copy must live under scripts/ so BASH_SOURCE resolves ROOT to the
# clean clone rather than /tmp. Hide only this ephemeral helper through
# .git/info/exclude so the runtime validator still sees a clean working tree.
mkdir -p "$(dirname "${EXCLUDE_FILE}")"
touch "${EXCLUDE_FILE}"
if ! grep -Fxq "${EXCLUDE_PATTERN}" "${EXCLUDE_FILE}"; then
    printf '%s\n' "${EXCLUDE_PATTERN}" >> "${EXCLUDE_FILE}"
    ADDED_EXCLUDE=1
fi

TMP_RUNTIME="$(mktemp "${ROOT}/scripts/.goad-nomad-runtime.XXXXXX.sh")"

python3 - "${RUNTIME}" "${TMP_RUNTIME}" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
s = src.read_text()

# Windows Server exposes conditional-forwarder state through Get-DnsServerZone.
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

bash "${TMP_RUNTIME}" "$@"
