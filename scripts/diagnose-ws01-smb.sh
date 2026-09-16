#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

provider_dir="${GOAD_PROVIDER_DIR:-}"
if [[ -z "${provider_dir}" ]]; then
    mapfile -t ws01_ids < <(find "${ROOT}/workspace" -type f -path '*/provider/.vagrant/machines/GOAD-WS01/vmware_desktop/id' -print)
    [[ ${#ws01_ids[@]} -eq 1 ]] || fail 'Cannot select one installed Kingdoms instance; set GOAD_PROVIDER_DIR explicitly.'
    provider_dir="${ws01_ids[0]%%/.vagrant/*}"
fi
readonly PROVIDER_DIR="${provider_dir}"
readonly INSTANCE_DIR="$(dirname "${PROVIDER_DIR}")"
readonly INSTANCE_INVENTORY="${INSTANCE_DIR}/inventory"
readonly LAB_INVENTORY="${ROOT}/ad/GOAD/data/inventory"
readonly GLOBAL_INVENTORY="${ROOT}/globalsettings.ini"
readonly ANSIBLE_PLAYBOOK="${HOME}/.goad/.venv/bin/ansible-playbook"
readonly WS01_IP="10.4.10.31"

[[ -x "${ANSIBLE_PLAYBOOK}" ]] || fail "GOAD Ansible runtime missing: ${ANSIBLE_PLAYBOOK}"
[[ -f "${INSTANCE_INVENTORY}" ]] || fail "instance inventory missing: ${INSTANCE_INVENTORY}"
command -v nc >/dev/null 2>&1 || fail 'nc is required'
command -v smbclient >/dev/null 2>&1 || fail 'smbclient is required'

bash scripts/verify-test-source.sh

echo
echo '============================================================'
echo 'GOAD KINGDOMS — WS01 SMB DIAGNOSTIC (READ ONLY)'
echo '============================================================'

echo
echo '=== 1. OPERATOR NETWORK VIEW ==='
if nc -z -w 3 "${WS01_IP}" 445 >/dev/null 2>&1; then
    echo '[PASS] TCP/445 reachable from operator host.'
else
    echo '[INFO] TCP/445 is not reachable from operator host.'
fi

for mode in null guest; do
    echo
    echo "--- smbclient ${mode} probe ---"
    set +e
    if [[ "${mode}" == "null" ]]; then
        smbclient -g -N -U '%' -L "//${WS01_IP}" 2>&1
    else
        smbclient -g -N -U 'Guest%' -L "//${WS01_IP}" 2>&1
    fi
    rc=$?
    set -e
    echo "[exit_code=${rc}]"
done

TMP_PLAYBOOK="$(mktemp --suffix=.yml)"
trap 'rm -f "${TMP_PLAYBOOK}"' EXIT
cat > "${TMP_PLAYBOOK}" <<'YAML'
---
- name: Diagnose GOAD Kingdoms WS01 SMB state
  hosts: ws01
  gather_facts: false
  tasks:
    - name: Read SMB service, listener, network profile and firewall state
      ansible.windows.win_powershell:
        script: |
          $ErrorActionPreference = 'Stop'
          $Ansible.Changed = $false

          $service = Get-Service -Name LanmanServer -ErrorAction SilentlyContinue
          $listeners = @(
              Get-NetTCPConnection -LocalPort 445 -State Listen -ErrorAction SilentlyContinue |
              Select-Object LocalAddress, LocalPort, OwningProcess, State
          )
          $profiles = @(
              Get-NetConnectionProfile -ErrorAction SilentlyContinue |
              Select-Object Name, InterfaceAlias, NetworkCategory, IPv4Connectivity, IPv6Connectivity
          )
          $firewallProfiles = @(
              Get-NetFirewallProfile -ErrorAction SilentlyContinue |
              Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
          )
          $sharingRules = @(
              Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -ErrorAction SilentlyContinue |
              Select-Object DisplayName, Enabled, Profile, Direction, Action
          )
          $smbConfig = Get-SmbServerConfiguration -ErrorAction SilentlyContinue |
              Select-Object EnableSMB1Protocol, EnableSMB2Protocol, EncryptData, RejectUnencryptedAccess

          [pscustomobject]@{
              ComputerName = $env:COMPUTERNAME
              LanmanServer = if ($service) { [pscustomobject]@{ Status=$service.Status.ToString(); StartType=$service.StartType.ToString() } } else { $null }
              Port445Listeners = $listeners
              NetworkProfiles = $profiles
              FirewallProfiles = $firewallProfiles
              FileAndPrinterSharingRules = $sharingRules
              SmbServerConfiguration = $smbConfig
          } | ConvertTo-Json -Depth 6
      changed_when: false
      register: ws01_smb_diag

    - name: Show WS01 SMB diagnostic
      ansible.builtin.debug:
        var: ws01_smb_diag.output
YAML

echo
echo '=== 2. WINDOWS SMB / FIREWALL VIEW ==='
ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg" \
    "${ANSIBLE_PLAYBOOK}" \
    -i "${LAB_INVENTORY}" \
    -i "${INSTANCE_INVENTORY}" \
    -i "${GLOBAL_INVENTORY}" \
    "${TMP_PLAYBOOK}"

echo
echo '============================================================'
echo 'DIAGNOSTIC COMPLETE — no WS01 configuration was changed.'
echo '============================================================'
