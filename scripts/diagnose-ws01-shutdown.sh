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

readonly PROVIDER_DIR="${GOAD_PROVIDER_DIR:-}"
[[ -n "${PROVIDER_DIR}" ]] || fail 'GOAD_PROVIDER_DIR is required'
[[ -d "${PROVIDER_DIR}" ]] || fail "GOAD_PROVIDER_DIR does not exist: ${PROVIDER_DIR}"

readonly INSTANCE_DIR="$(dirname "${PROVIDER_DIR}")"
readonly INSTANCE_INVENTORY="${INSTANCE_DIR}/inventory"
readonly LAB_INVENTORY="${ROOT}/ad/GOAD/data/inventory"
readonly GLOBAL_INVENTORY="${ROOT}/globalsettings.ini"
readonly ANSIBLE_PLAYBOOK="${HOME}/.goad/.venv/bin/ansible-playbook"
readonly WS01_ID_FILE="${PROVIDER_DIR}/.vagrant/machines/GOAD-WS01/vmware_desktop/id"

[[ -x "${ANSIBLE_PLAYBOOK}" ]] || fail "GOAD Ansible runtime missing: ${ANSIBLE_PLAYBOOK}"
[[ -f "${INSTANCE_INVENTORY}" ]] || fail "instance inventory missing: ${INSTANCE_INVENTORY}"
[[ -f "${LAB_INVENTORY}" ]] || fail "lab inventory missing: ${LAB_INVENTORY}"
[[ -f "${GLOBAL_INVENTORY}" ]] || fail "global inventory missing: ${GLOBAL_INVENTORY}"
[[ -f "${WS01_ID_FILE}" ]] || fail "WS01 VMware id file missing: ${WS01_ID_FILE}"
command -v vmrun >/dev/null 2>&1 || fail 'vmrun is required'
command -v nc >/dev/null 2>&1 || fail 'nc is required'

readonly WS01_VMX="$(cat "${WS01_ID_FILE}")"
[[ -f "${WS01_VMX}" ]] || fail "WS01 VMX does not exist: ${WS01_VMX}"
readonly WS01_LOG="$(dirname "${WS01_VMX}")/vmware.log"

bash scripts/verify-test-source.sh
pass 'Git source-of-truth gate'

ws01_running() {
    vmrun -T ws list 2>/dev/null | grep -Fxq "${WS01_VMX}"
}

wait_for_winrm() {
    local deadline=$((SECONDS + 300))
    while (( SECONDS < deadline )); do
        if nc -z -w 2 10.4.10.31 5986 >/dev/null 2>&1; then
            return 0
        fi
        sleep 5
    done
    return 1
}

cleanup() {
    rm -f "${TMP_PLAYBOOK:-}" 2>/dev/null || true
}
trap cleanup EXIT

echo
echo '============================================================'
echo 'GOAD KINGDOMS — WS01 SHUTDOWN DIAGNOSTIC'
echo '============================================================'

echo
echo '=== 1. CURRENT POWER STATE ==='
if ws01_running; then
    echo '[PASS] WS01 is already powered on.'
else
    echo '[INFO] WS01 is powered off; starting only WS01 without provisioning.'
    vmrun -T ws start "${WS01_VMX}" nogui >/dev/null
    pass 'WS01 power-on requested'
fi

echo
echo '=== 2. WAIT FOR EXERCISE WINRM ==='
wait_for_winrm || {
    echo '[FAIL] WS01 did not expose TCP/5986 within 5 minutes.'
    echo '--- VMware power evidence ---'
    grep -Ei 'softPowerOff|power.?off|shutdown|panic|crash|VMX exit' "${WS01_LOG}" 2>/dev/null | tail -n 60 || true
    exit 1
}
pass 'WS01 WinRM TCP/5986 reachable'

TMP_PLAYBOOK="$(mktemp --suffix=.yml)"
cat > "${TMP_PLAYBOOK}" <<'YAML'
---
- name: Diagnose GOAD Kingdoms WS01 shutdown
  hosts: ws01
  gather_facts: false
  tasks:
    - name: Read recent Windows shutdown and licensing evidence
      ansible.windows.win_powershell:
        script: |
          $ErrorActionPreference = 'Stop'
          $start = (Get-Date).AddHours(-12)
          $events = Get-WinEvent -FilterHashtable @{
              LogName='System'
              Id=1074,6006,6008,41
              StartTime=$start
          } -ErrorAction SilentlyContinue |
              Sort-Object TimeCreated -Descending |
              Select-Object -First 20 TimeCreated, Id, ProviderName, LevelDisplayName, Message

          $license = Get-CimInstance SoftwareLicensingProduct -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like 'Windows*' -and $_.PartialProductKey } |
              Select-Object Name, Description, LicenseStatus, GracePeriodRemaining, PartialProductKey

          $computer = Get-CimInstance Win32_ComputerSystem
          $os = Get-CimInstance Win32_OperatingSystem

          [pscustomobject]@{
              ComputerName = $computer.Name
              Domain = $computer.Domain
              PartOfDomain = $computer.PartOfDomain
              Caption = $os.Caption
              Version = $os.Version
              LastBootUpTime = $os.LastBootUpTime
              ShutdownEvents = @($events)
              Licensing = @($license)
          } | ConvertTo-Json -Depth 6
      register: ws01_shutdown_diagnostic

    - name: Show WS01 shutdown diagnostic
      ansible.builtin.debug:
        var: ws01_shutdown_diagnostic.output
YAML

echo
echo '=== 3. WINDOWS SHUTDOWN / LICENSE EVIDENCE ==='
ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg" \
    "${ANSIBLE_PLAYBOOK}" \
    -i "${LAB_INVENTORY}" \
    -i "${INSTANCE_INVENTORY}" \
    -i "${GLOBAL_INVENTORY}" \
    "${TMP_PLAYBOOK}"

echo
echo '=== 4. VMWARE CLEAN-SHUTDOWN EVIDENCE ==='
grep -Ei 'softPowerOff|Issuing power-off request|cleanShutdown|VMX exit|panic|crash' "${WS01_LOG}" 2>/dev/null | tail -n 60 || true

echo
echo '============================================================'
echo 'DIAGNOSTIC COMPLETE'
echo 'WS01 was powered on only; no provisioning/configuration was changed.'
echo '============================================================'
