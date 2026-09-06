#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

python3 - <<'PY'
from pathlib import Path

profile_path = Path('goad/provider/vagrant/vmware_kingdoms_profile.py')
factory_path = Path('goad/provider/provider_factory.py')
ansible_path = Path('goad/provisioner/ansible/ansible.py')
base_path = Path('goad/provider/vagrant/vmware_kingdoms.py')

for path in (profile_path, factory_path, ansible_path, base_path):
    source = path.read_text(encoding='utf-8')
    compile(source, str(path), 'exec')

profile = profile_path.read_text(encoding='utf-8')
factory = factory_path.read_text(encoding='utf-8')
ansible = ansible_path.read_text(encoding='utf-8')
base = base_path.read_text(encoding='utf-8')

required_profile = (
    'class ProfiledGoadKingdomsVmwareProvider(GoadKingdomsVmwareProvider):',
    'result = super().install()',
    'original_run_vagrant = self.command.run_vagrant',
    'self.command.run_vagrant = original_run_vagrant',
    'GOAD Kingdoms install timing:',
    "'Host/network preflight'",
    "'GOAD-ROUTER bring-up'",
    'VMware Tools / forwarded WinRM readiness',
    'failed-first-up recovery cycle',
)
for token in required_profile:
    if token not in profile:
        raise SystemExit(f'missing install-profile token: {token}')

if 'ProfiledGoadKingdomsVmwareProvider(lab_name)' not in factory:
    raise SystemExit('provider factory is not using the profiling wrapper')

required_ansible = (
    '=== KINGDOMS INSTALL TIMING SUMMARY ===',
    'Provisioning management-plane preparation',
    'Playbook {playbook}',
    'Final exercise-mode transition',
    'END-TO-END',
)
for token in required_ansible:
    if token not in ansible:
        raise SystemExit(f'missing Ansible timing token: {token}')

# Guard the core fresh-install lifecycle contract while this branch measures it.
# Optimization belongs in a later change after real timing data exists.
required_base = (
    "first_up = self.command.run_vagrant(['up', machine], self.path)",
    'if not self._ensure_vmware_tools(machine):',
    'if not self._recover_failed_windows_vagrant_up(machine):',
    "self._run_vagrant_bounded(['up', machine, '--provision'], timeout=600)",
)
for token in required_base:
    if token not in base:
        raise SystemExit(f'fresh-install lifecycle contract changed unexpectedly: {token}')

# The profiling wrapper must observe lifecycle calls, not introduce a second
# VMware controller of its own.
for forbidden in ('vmrun', 'subprocess.run(', 'subprocess.Popen('):
    if forbidden in profile:
        raise SystemExit(f'profiling wrapper must not own lifecycle operation: {forbidden}')

print('KINGDOMS install profiling source validation passed')
PY
