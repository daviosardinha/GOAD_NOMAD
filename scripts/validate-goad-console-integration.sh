#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_DIR="$(mktemp -d /tmp/goad-nomad-console-validation.XXXXXX)"

SOURCE_INSTANCE="${1:-${GOAD_SOURCE_INSTANCE:-}}"
CREATED_LINK=0
INSTANCE_ID=""
TARGET_INSTANCE=""

fail() {
    echo "[FAIL] $*" >&2
    echo "Logs: ${LOG_DIR}" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

cleanup() {
    if [[ "${CREATED_LINK}" -eq 1 && -L "${TARGET_INSTANCE}" ]]; then
        rm -f "${TARGET_INSTANCE}"
    fi
}
trap cleanup EXIT

if [[ -z "${SOURCE_INSTANCE}" ]]; then
    mapfile -t candidates < <(
        find "${HOME}/Documents/GOAD_NOMAD/workspace" \
            -mindepth 1 -maxdepth 1 -type d -name '*-goad-vmware' \
            -print 2>/dev/null || true
    )

    if [[ ${#candidates[@]} -eq 1 ]]; then
        SOURCE_INSTANCE="${candidates[0]}"
    else
        fail "Pass the existing deployed instance path, e.g. bash scripts/validate-goad-console-integration.sh ~/Documents/GOAD_NOMAD/workspace/<instance-id>"
    fi
fi

SOURCE_INSTANCE="$(realpath "${SOURCE_INSTANCE}")"
[[ -f "${SOURCE_INSTANCE}/instance.json" ]] || fail "instance.json not found under ${SOURCE_INSTANCE}"

INSTANCE_ID="$(basename "${SOURCE_INSTANCE}")"
TARGET_INSTANCE="${ROOT}/workspace/${INSTANCE_ID}"

python3 - "${SOURCE_INSTANCE}/instance.json" <<'PY' || fail "source instance is not GOAD/vmware"
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    d = json.load(f)
assert d.get('lab') == 'GOAD', d
assert d.get('provider') == 'vmware', d
PY

mkdir -p "${ROOT}/workspace"
if [[ ! -e "${TARGET_INSTANCE}" ]]; then
    ln -s "${SOURCE_INSTANCE}" "${TARGET_INSTANCE}"
    CREATED_LINK=1
elif [[ "$(realpath "${TARGET_INSTANCE}")" != "${SOURCE_INSTANCE}" ]]; then
    fail "${TARGET_INSTANCE} already exists and does not point to ${SOURCE_INSTANCE}"
fi

cd "${ROOT}"

section "1. SOURCE / ENTRYPOINT PREFLIGHT"
[[ -d .git ]] || fail "run this from a Git clone"
git diff --check
pass "git whitespace check"

bash -n goad.sh
bash -n scripts/lab-mode.sh
bash -n scripts/validate-network-segmentation.sh
pass "shell syntax"

python3 -m py_compile \
    goad_nomad.py \
    goad/provider/provider_factory.py \
    goad/provider/vagrant/vmware_nomad.py \
    goad/provisioner/ansible/ansible.py \
    goad/settings.py \
    goad/instances.py
pass "Python syntax"

grep -Fq 'goad_nomad.py "$@"' goad.sh || fail "goad.sh does not launch goad_nomad.py"
grep -Fq 'GoadNomadVmwareProvider' goad/provider/provider_factory.py || fail "GOAD_NOMAD VMware provider is not wired into ProviderFactory"
grep -Fq "network_scope = '10.4.0.0/16 (segmented)'" goad/provider/vagrant/vmware_nomad.py || fail "segmented network scope missing"
grep -Fq "('NORTH', 'vmnet10', '10.4.10.0/24')" goad/provider/vagrant/vmware_nomad.py || fail "NORTH profile missing"
grep -Fq "('SEVENKINGDOMS', 'vmnet20', '10.4.20.0/24')" goad/provider/vagrant/vmware_nomad.py || fail "SEVENKINGDOMS profile missing"
grep -Fq "('ESSOS', 'vmnet30', '10.4.30.0/24')" goad/provider/vagrant/vmware_nomad.py || fail "ESSOS profile missing"
grep -Fq "('MANAGEMENT', 'vmnet99', '10.4.99.0/24')" goad/provider/vagrant/vmware_nomad.py || fail "MANAGEMENT profile missing"
pass "GOAD_NOMAD console/provider wiring"

[[ -x "${HOME}/.goad/.venv/bin/python3" || -x "${HOME}/.goad/.venv/bin/python" ]] || fail "GOAD venv missing; run ./goad.sh once to bootstrap dependencies"

section "2. GOAD.SH STATUS THROUGH EXISTING INSTANCE"
./goad.sh -t status -i "${INSTANCE_ID}" 2>&1 | tee "${LOG_DIR}/status-before.log"
grep -Fq 'Network Scope : 10.4.0.0/16 (segmented)' "${LOG_DIR}/status-before.log" || fail "status does not report segmented network scope"
grep -Fq 'Network Mode  : exercise' "${LOG_DIR}/status-before.log" || fail "existing lab is not currently in exercise mode"
pass "goad.sh status reports segmented exercise state"

section "3. INTERACTIVE CONSOLE COMMANDS / MODE ROUND-TRIP"
sudo -v
{
    printf 'load %s\n' "${INSTANCE_ID}"
    printf 'network\n'
    printf 'mode status\n'
    printf 'mode provisioning\n'
    printf 'mode status\n'
    printf 'mode exercise\n'
    printf 'mode status\n'
    printf 'set_ip_range 192.168.56\n'
    printf 'network\n'
    printf 'status\n'
    printf 'exit\n'
} | ./goad.sh 2>&1 | tee "${LOG_DIR}/interactive.log"

grep -Fq 'GOAD_NOMAD Network Scope: 10.4.0.0/16 (segmented)' "${LOG_DIR}/interactive.log" || fail "interactive network command failed"
grep -Fq 'GOAD_NOMAD mode is now provisioning' "${LOG_DIR}/interactive.log" || fail "interactive provisioning-mode transition failed"
grep -Fq 'GOAD_NOMAD mode is now exercise' "${LOG_DIR}/interactive.log" || fail "interactive exercise-mode transition failed"
grep -Fq 'GOAD/VMware uses the fixed GOAD_NOMAD segmented profile' "${LOG_DIR}/interactive.log" || fail "legacy set_ip_range override was not blocked"
grep -Fq 'vmnet10' "${LOG_DIR}/interactive.log" || fail "NORTH vmnet missing from interactive network output"
grep -Fq 'vmnet20' "${LOG_DIR}/interactive.log" || fail "SEVENKINGDOMS vmnet missing from interactive network output"
grep -Fq 'vmnet30' "${LOG_DIR}/interactive.log" || fail "ESSOS vmnet missing from interactive network output"
grep -Fq 'vmnet99' "${LOG_DIR}/interactive.log" || fail "MANAGEMENT vmnet missing from interactive network output"
pass "interactive console and reversible network modes"

section "4. COMPLETE MILESTONE 1 VALIDATION THROUGH GOAD.SH"
./goad.sh -t validate -i "${INSTANCE_ID}" 2>&1 | tee "${LOG_DIR}/validate.log"
grep -Fq '[PASSED] NETWORK SEGMENTATION RUNTIME VALIDATION PASSED' "${LOG_DIR}/validate.log" || \
    grep -Fq 'GOAD_NOMAD runtime validation passed' "${LOG_DIR}/validate.log" || \
    fail "full runtime validator did not report success"
pass "complete runtime validator reached through goad.sh"

section "5. FINAL INSTALLED / EXERCISE STATE"
./goad.sh -t status -i "${INSTANCE_ID}" 2>&1 | tee "${LOG_DIR}/status-after.log"
grep -Fq 'Network Scope : 10.4.0.0/16 (segmented)' "${LOG_DIR}/status-after.log" || fail "final network scope is incorrect"
grep -Fq 'Network Mode  : exercise' "${LOG_DIR}/status-after.log" || fail "validator did not leave the lab in exercise mode"

python3 - "${SOURCE_INSTANCE}/instance.json" <<'PY' || fail "instance metadata was not promoted to installed"
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    d = json.load(f)
assert d.get('status') == 'installed', d.get('status')
PY
pass "instance metadata status=installed"

if ip route show 10.4.20.0/24 | grep -q .; then
    fail "provisioning route to 10.4.20.0/24 still exists"
fi
if ip route show 10.4.30.0/24 | grep -q .; then
    fail "provisioning route to 10.4.30.0/24 still exists"
fi
pass "protected-zone host routes absent"

GOAD_PROVIDER_DIR="${SOURCE_INSTANCE}/provider" bash scripts/lab-mode.sh status 2>&1 | tee "${LOG_DIR}/lab-mode-final.log"
grep -Fq 'Recorded mode: exercise' "${LOG_DIR}/lab-mode-final.log" || fail "lab-mode final state is not exercise"
for vm in GOAD-DC01 GOAD-DC02 GOAD-DC03 GOAD-SRV02 GOAD-SRV03 GOAD-WS01; do
    awk -v vm="--- ${vm} ---" '
        $0 == vm {inside=1; next}
        inside && /^--- / {exit}
        inside && /ethernet0.startConnected=FALSE/ {found=1}
        END {exit(found ? 0 : 1)}
    ' "${LOG_DIR}/lab-mode-final.log" || fail "${vm} provisioning NAT is not persistently isolated"
done
pass "all Windows provisioning NAT adapters isolated"

section "GOAD_NOMAD CONSOLE INTEGRATION SUMMARY"
echo "[PASS] ./goad.sh is the canonical GOAD_NOMAD entry point"
echo "[PASS] GOAD/VMware reports 10.4.0.0/16 segmented scope"
echo "[PASS] interactive network/mode commands work"
echo "[PASS] provisioning -> exercise round-trip works"
echo "[PASS] legacy flat set_ip_range is blocked for GOAD/VMware"
echo "[PASS] complete Milestone 1 validator runs through ./goad.sh"
echo "[PASS] final state is installed + exercise"
echo "[PASS] no protected-zone host-route bypass remains"
echo "[PASS] all six Windows provisioning NAT adapters are isolated"
echo
echo "Logs: ${LOG_DIR}"
echo
echo "[READY] Existing-lab GOAD_NOMAD console acceptance passed."
echo "        The remaining final acceptance test is a genuinely fresh GOAD/VMware install started only through ./goad.sh."
