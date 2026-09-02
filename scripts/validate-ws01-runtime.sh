#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_DIR="${GOAD_KINGDOMS_WS01_LOG_DIR:-/tmp/goad-kingdoms-ws01-$(date +%Y%m%d-%H%M%S)}"
readonly INVENTORY_DATA="${ROOT}/ad/GOAD/data/inventory"
readonly INVENTORY_PROVIDER="${ROOT}/ad/GOAD/providers/vmware/inventory"
readonly ANSIBLE_CFG="${ROOT}/ansible/ansible.cfg"

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    printf 'Logs: %s\n' "${LOG_DIR}" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

find_ansible_playbook() {
    local -a candidates=(
        "$(command -v ansible-playbook 2>/dev/null || true)"
        "${ROOT}/.venv/bin/ansible-playbook"
        "${ROOT}/venv/bin/ansible-playbook"
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

resolve_provider() {
    if [[ -n "${GOAD_PROVIDER_DIR:-}" ]]; then
        [[ -d "${GOAD_PROVIDER_DIR}" ]] || fail "GOAD_PROVIDER_DIR does not exist: ${GOAD_PROVIDER_DIR}"
        PROVIDER="${GOAD_PROVIDER_DIR}"
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
    PROVIDER="${ids[0]%%/.vagrant/*}"
}

mkdir -p "${LOG_DIR}"
cd "${ROOT}"

bash scripts/verify-test-source.sh | tee "${LOG_DIR}/source-gate.log"
pass "Git source-of-truth gate"

resolve_provider
[[ -f "${PROVIDER}/.goad-nomad-mode" ]] || fail 'segmented mode state is missing'
[[ "$(<"${PROVIDER}/.goad-nomad-mode")" == 'exercise' ]] || fail 'WS01 runtime validation must start in exercise mode'
pass "recorded exercise mode"

readonly ID_FILE="${PROVIDER}/.vagrant/machines/GOAD-WS01/vmware_desktop/id"
[[ -f "${ID_FILE}" ]] || fail "GOAD-WS01 Vagrant id is missing: ${ID_FILE}"
readonly VMX="$(<"${ID_FILE}")"
[[ -f "${VMX}" ]] || fail "GOAD-WS01 VMX is missing: ${VMX}"

grep -Eiq '^ethernet0\.connectiontype[[:space:]]*=[[:space:]]*"nat"' "${VMX}" || fail 'WS01 ethernet0 is not provisioning NAT'
grep -Eiq '^ethernet0\.startconnected[[:space:]]*=[[:space:]]*"false"' "${VMX}" || fail 'WS01 provisioning NAT is not persistently disabled'
grep -Eiq '^ethernet1\.connectiontype[[:space:]]*=[[:space:]]*"custom"' "${VMX}" || fail 'WS01 ethernet1 is not a custom exercise NIC'
grep -Eiq '^ethernet1\.vnet[[:space:]]*=[[:space:]]*"vmnet10"' "${VMX}" || fail 'WS01 exercise NIC is not attached to vmnet10'
pass "WS01 persistent two-NIC exercise layout"

# Windows Firewall remains enabled on the clean WS01 baseline, so ICMP echo is
# not a valid reachability contract. Prove NORTH connectivity using the actual
# services required by the exercise and management paths instead.
command -v nc >/dev/null 2>&1 || fail 'nc is required for WS01 TCP reachability validation'
timeout 3 nc -zw2 10.4.10.31 3389 >/dev/null 2>&1 || fail 'WS01 RDP is not reachable from NORTH'
timeout 3 nc -zw2 10.4.10.31 5986 >/dev/null 2>&1 || fail 'WS01 WinRM HTTPS is not reachable from NORTH'
pass "WS01 NORTH TCP reachability, RDP foothold and WinRM management services"

ANSIBLE_PLAYBOOK="$(find_ansible_playbook || true)"
[[ -n "${ANSIBLE_PLAYBOOK}" ]] || fail 'ansible-playbook was not found'

cat > "${LOG_DIR}/ws01-runtime.yml" <<'YAML'
---
- name: Validate the GOAD Kingdoms WS01 clean foundation
  hosts: ws01
  gather_facts: false
  tasks:
    - name: Validate WS01 foundation state
      ansible.windows.win_powershell:
        script: |
          $ErrorActionPreference = 'Stop'

          $computer = Get-CimInstance Win32_ComputerSystem
          if (-not $computer.PartOfDomain) { throw 'WS01 is not domain joined' }
          if ($computer.Domain -ne 'north.sevenkingdoms.local') { throw "domain=$($computer.Domain)" }
          if (-not (Test-ComputerSecureChannel)) { throw 'domain secure channel is unhealthy' }

          $rdpUsers = @(Get-LocalGroupMember 'Remote Desktop Users' | ForEach-Object Name)
          if (($rdpUsers | ForEach-Object ToLowerInvariant) -notcontains 'north\rickon.stark') {
              throw "Rickon missing from RDP group: $($rdpUsers -join ',')"
          }

          $admins = @(Get-LocalGroupMember 'Administrators' | ForEach-Object Name)
          if (($admins | ForEach-Object ToLowerInvariant) -contains 'north\rickon.stark') {
              throw 'Rickon is unexpectedly a local administrator'
          }

          $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').EnableLUA
          if ($uac -ne 1) { throw "UAC EnableLUA=$uac" }

          $disabledFirewall = @(Get-NetFirewallProfile | Where-Object { -not $_.Enabled })
          if ($disabledFirewall.Count -ne 0) { throw "disabled firewall profiles=$($disabledFirewall.Name -join ',')" }

          $defender = Get-MpComputerStatus
          if (-not $defender.AntivirusEnabled) { throw 'Defender antivirus is disabled' }
          if (-not $defender.RealTimeProtectionEnabled) { throw 'Defender real-time protection is disabled' }

          $eval = Get-CimInstance SoftwareLicensingProduct -ErrorAction SilentlyContinue |
              Where-Object {
                  $_.Name -like 'Windows*' -and
                  $_.PartialProductKey -and
                  $_.Description -match 'TIMEBASED_EVAL'
              } |
              Select-Object -First 1
          if ($eval) {
              if ([int64]$eval.GracePeriodRemaining -le 0) {
                  throw "Windows evaluation is expired; status=$($eval.LicenseStatus) grace=$($eval.GracePeriodRemaining)"
              }
              Write-Output "WS01_EVAL_GRACE_MINUTES=$($eval.GracePeriodRemaining)"
          }
          Write-Output 'WS01_EVAL_READY=PASS'
          Write-Output 'WS01_FOUNDATION=PASS'
      register: ws01_validation

    - name: Show WS01 validation output
      ansible.builtin.debug:
        var: ws01_validation.output
YAML

(
    cd "${ROOT}/ansible"
    ANSIBLE_CONFIG="${ANSIBLE_CFG}" \
        timeout 900 "${ANSIBLE_PLAYBOOK}" \
            -i "${INVENTORY_DATA}" \
            -i "${INVENTORY_PROVIDER}" \
            "${LOG_DIR}/ws01-runtime.yml"
) 2>&1 | tee "${LOG_DIR}/ansible.log"

grep -Fq 'WS01_EVAL_READY=PASS' "${LOG_DIR}/ansible.log" || fail 'WS01 Windows evaluation grace check did not pass'
grep -Fq 'WS01_FOUNDATION=PASS' "${LOG_DIR}/ansible.log" || fail 'WS01 PowerShell foundation checks did not pass'
grep -Eq 'failed=0.*unreachable=0|unreachable=0.*failed=0' "${LOG_DIR}/ansible.log" || fail 'WS01 Ansible validation did not finish cleanly'
pass "WS01 domain, Rickon rights, UAC, Firewall, Defender and evaluation grace"

printf '\n[READY] GOAD Kingdoms WS01 runtime validation passed.\n'
printf 'Logs: %s\n' "${LOG_DIR}"
