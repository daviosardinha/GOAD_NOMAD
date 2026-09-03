#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

printf '\n============================================================\n'
printf 'GOAD KINGDOMS — CLEAN-INSTALL SOURCE GATE\n'
printf '============================================================\n\n'

bash scripts/verify-test-source.sh
pass 'Git source-of-truth gate'

readonly REQUIRED=(
    goad.sh
    goad/provisioner/ansible/ansible.py
    goad/provider/provider_factory.py
    goad/provider/vagrant/vmware_kingdoms.py
    playbooks.yml
    ansible/ws01.yml
    ansible/ws01-lpe-install.yml
    ansible/windows-lpe.yml
    ad/GOAD/data/config.json
    ad/GOAD/data/inventory
    ad/GOAD/providers/vmware/Vagrantfile
    ad/GOAD/providers/vmware/inventory
    scripts/validate-network-segmentation-source.sh
    scripts/validate-ws01-source.sh
    scripts/validate-windows-lpe-framework-source.sh
)
for file in "${REQUIRED[@]}"; do
    [[ -f "${file}" ]] || fail "required clean-install source is missing: ${file}"
done
pass 'required GOAD Kingdoms clean-install source files'

bash -n scripts/validate-goad-kingdoms-install-source.sh
pass 'clean-install gate shell syntax'

python3 - <<'PY'
from pathlib import Path
import re
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f'PyYAML is required to validate playbooks.yml: {exc}')


def fail(message):
    raise SystemExit(message)

playbooks = yaml.safe_load(Path('playbooks.yml').read_text())
expected = [
    'build.yml',
    'ad-servers.yml',
    'ad-parent_domain.yml',
    'ad-child_domain.yml',
    'wait5m.yml',
    'ad-members.yml',
    'ad-trusts.yml',
    'ad-data.yml',
    'ws01.yml',
    'ad-gmsa.yml',
    'laps.yml',
    'ad-relations.yml',
    'adcs.yml',
    'ad-acl.yml',
    'servers.yml',
    'security.yml',
    'vulnerabilities.yml',
    'ws01-lpe-install.yml',
]
actual = playbooks.get('GOAD')
if actual != expected:
    fail(f'GOAD clean-install playbook sequence mismatch:\nexpected={expected}\nactual={actual}')
if actual.index('ws01.yml') <= actual.index('ad-data.yml'):
    fail('ws01.yml must run after ad-data.yml so NORTH\\rickon.stark exists')
if actual[-1] != 'ws01-lpe-install.yml':
    fail('WS01 full LPE seeding must be the final GOAD Ansible stage')

install_lpe = Path('ansible/ws01-lpe-install.yml').read_text()
for token in (
    'hosts: ws01',
    'role: windows_lpe',
    'windows_lpe_action: apply',
    'windows_lpe_profile: full-lpe',
):
    if token not in install_lpe:
        fail(f'WS01 LPE clean-install playbook missing contract: {token}')
if 'windows_lpe_allow_candidate' in install_lpe:
    fail('promoted clean install must not require candidate opt-in')

foundation = Path('ansible/ws01.yml').read_text()
for token in (
    'hosts: ws01',
    "role: 'settings/eval_rearm'",
    "role: 'commonwkstn'",
    "role: 'settings/adjust_rights'",
    "role: 'settings/user_rights'",
):
    if token not in foundation:
        fail(f'WS01 clean foundation playbook missing contract: {token}')

config = Path('ad/GOAD/data/config.json').read_text()
if '"ws01"' not in config or '"north\\\\rickon.stark"' not in config:
    fail('GOAD data does not define WS01 with Rickon foothold rights')

inventory = Path('ad/GOAD/data/inventory').read_text()
if not re.search(r'(?m)^ws01\s*$', inventory):
    fail('GOAD lab inventory does not include ws01')

provider_inventory = Path('ad/GOAD/providers/vmware/inventory').read_text()
if not re.search(
    r'(?m)^ws01\s+ansible_host=10\.4\.10\.31\s+dns_domain=dc02\s+dict_key=ws01\s*$',
    provider_inventory,
):
    fail('GOAD VMware provider inventory does not pin ws01 to 10.4.10.31')

provider_factory = Path('goad/provider/provider_factory.py').read_text()
if 'GoadKingdomsVmwareProvider' not in provider_factory:
    fail('VMware provider factory is not wired to GOAD Kingdoms segmented provider')

kingdoms_provider = Path('goad/provider/vagrant/vmware_kingdoms.py').read_text()
for token in (
    'def _ensure_vmware_tools(self, machine):',
    "['halt', machine, '-f']",
    "['up', machine, '--provision']",
    'completed a clean post-Tools Vagrant provision cycle',
):
    if token not in kingdoms_provider:
        fail(f'GOAD Kingdoms VMware Tools recovery contract missing: {token}')

provisioner = Path('goad/provisioner/ansible/ansible.py').read_text()
for token in ('_prepare_provider_provisioning', '_finalize_provider_provisioning', 'get_playbook_list'):
    if token not in provisioner:
        fail(f'Ansible clean-install lifecycle missing provider hook: {token}')
PY
pass 'GOAD clean-install orchestration contract'

readonly ANSIBLE_PLAYBOOK="${HOME}/.goad/.venv/bin/ansible-playbook"
if [[ -x "${ANSIBLE_PLAYBOOK}" ]]; then
    ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg" \
        "${ANSIBLE_PLAYBOOK}" -i 'ws01,' "${ROOT}/ansible/ws01.yml" --syntax-check >/dev/null
    ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg" \
        "${ANSIBLE_PLAYBOOK}" -i 'ws01,' "${ROOT}/ansible/ws01-lpe-install.yml" --syntax-check >/dev/null
    pass 'WS01 foundation and install LPE Ansible syntax'
else
    printf '[INFO] GOAD Ansible runtime not installed yet; syntax checks deferred to bootstrap/runtime\n'
fi

bash scripts/validate-network-segmentation-source.sh
pass 'segmented VMware/provider source contract'

bash scripts/validate-ws01-source.sh
pass 'WS01 source contract'

bash scripts/validate-windows-lpe-framework-source.sh
pass '20-technique Windows LPE source contract'

git diff --check
pass 'Git whitespace check'

printf '\n[READY] GOAD Kingdoms clean-install source gate passed.\n'
printf 'A fresh GOAD/VMware install is wired to build segmentation, WS01 foundation, and all 20 LPE scenarios.\n'
