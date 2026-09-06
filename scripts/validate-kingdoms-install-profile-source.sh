#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

python3 - <<'PY'
import ast
from pathlib import Path

profile_path = Path('goad/provider/vagrant/vmware_kingdoms_profile.py')
factory_path = Path('goad/provider/provider_factory.py')
ansible_path = Path('goad/provisioner/ansible/ansible.py')
base_path = Path('goad/provider/vagrant/vmware_kingdoms.py')

for path in (profile_path, factory_path, ansible_path, base_path,
             Path('goad/install_profile.py'),
             Path('goad/provisioner/ansible/local.py'),
             Path('goad/command/cmd.py'),
             Path('ansible/callback_plugins/kingdoms_install_timing.py')):
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
# A Tools reporting repair must still preserve creation and provisioning.
required_base = (
    "first_up = self.command.run_vagrant(['up', machine], self.path)",
    'if not self._ensure_vmware_tools(machine):',
    'if not self._recover_failed_windows_vagrant_up(machine):',
    "self._run_vagrant_bounded(['up', machine, '--provision'], timeout=600)",
)
for token in required_base:
    if token not in base:
        raise SystemExit(f'fresh-install lifecycle contract changed unexpectedly: {token}')

# A VMware VM can inherit the Vagrant process group. Timeout handling must
# never signal that entire group, even when the controller has timed out.
for node in ast.walk(ast.parse(base)):
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
        if node.func.attr == 'killpg':
            raise SystemExit('Vagrant timeout cleanup must preserve VMware guest processes')

# The profiling wrapper must observe lifecycle calls, not introduce a second
# VMware controller of its own.
for forbidden in ('vmrun', 'subprocess.run(', 'subprocess.Popen('):
    if forbidden in profile:
        raise SystemExit(f'profiling wrapper must not own lifecycle operation: {forbidden}')

print('KINGDOMS install profiling source validation passed')
PY
