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
    goad_nomad.py
    goad/provisioner/ansible/ansible.py
    goad/provider/provider_factory.py
    goad/provider/vagrant/vmware.py
    goad/provider/vagrant/vmware_kingdoms.py
    playbooks.yml
    ansible/ws01.yml
    ansible/ws01-lpe-install.yml
    ansible/windows-lpe.yml
    ansible/roles/settings/enable_nat_adapter/tasks/main.yml
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
import ast
from pathlib import Path
import re
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f'PyYAML is required to validate playbooks.yml: {exc}')


def fail(message):
    raise SystemExit(message)


def require_tokens(label, text, tokens):
    for token in tokens:
        if token not in text:
            fail(f'{label} missing contract: {token}')


# Parse the Python sources without writing __pycache__ into the working tree.
for source in (
    'goad_nomad.py',
    'goad/provider/vagrant/vmware.py',
    'goad/provider/vagrant/vmware_kingdoms.py',
):
    text = Path(source).read_text()
    try:
        compile(text, source, 'exec')
    except SyntaxError as exc:
        fail(f'Python syntax error in {source}: {exc}')

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
require_tokens(
    'WS01 LPE clean-install playbook',
    install_lpe,
    (
        'hosts: ws01',
        'role: windows_lpe',
        'windows_lpe_action: apply',
        'windows_lpe_profile: full-lpe',
    ),
)
if 'windows_lpe_allow_candidate' in install_lpe:
    fail('promoted clean install must not require candidate opt-in')

foundation = Path('ansible/ws01.yml').read_text()
require_tokens(
    'WS01 clean foundation playbook',
    foundation,
    (
        'hosts: ws01',
        "role: 'settings/eval_rearm'",
        "role: 'commonwkstn'",
        "role: 'settings/adjust_rights'",
        "role: 'settings/user_rights'",
    ),
)

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

console = Path('goad_nomad.py').read_text()
require_tokens(
    'GOAD Kingdoms unattended sudo lifecycle',
    console,
    (
        'def _start_install_sudo_keepalive(self, stop_event):',
        "['sudo', '-k']",
        "['sudo', '-v']",
        "['sudo', '-n', '-v']",
        "name='goad-kingdoms-sudo-keepalive'",
        'non-interactive keepalive active every 60s',
        'sudo_lost_event.is_set()',
        'refusing to report the install as successful',
    ),
)

vmware_provider = Path('goad/provider/vagrant/vmware.py').read_text()
require_tokens(
    'VMware Tools recoverable-transition logging',
    vmware_provider,
    (
        'VMware Tools install/reboot interrupted WinRM',
        'validating guest recovery before classifying it as a failure',
        'recovery reboot closed WinRM',
        'continuing with readiness validation',
    ),
)
if 'VMware Tools WinRM session interrupted for' in vmware_provider:
    fail('expected VMware Tools transport teardown must not use the old failure-like warning text')

kingdoms_provider = Path('goad/provider/vagrant/vmware_kingdoms.py').read_text()
require_tokens(
    'GOAD Kingdoms failed Windows bring-up recovery',
    kingdoms_provider,
    (
        'def _wait_machine_stopped(self, machine, timeout=120):',
        'def _stop_failed_windows_guest_cleanly(self, machine):',
        'def _recover_failed_windows_vagrant_up(self, machine):',
        'def install(self):',
        "first_up = self.command.run_vagrant(['up', machine], self.path)",
        'if not first_up:',
        'if not self._recover_failed_windows_vagrant_up(machine):',
        'shutdown.exe /s /t 0 /f',
        "['vmrun', '-T', 'ws', 'stop', vmx, 'soft']",
        "['halt', machine, '-f']",
        "['up', machine, '--provision']",
        'timeout=600',
        'if not self._ensure_vmware_tools(machine):',
        'starting a clean recovery provision cycle',
        'completed a clean failed-bring-up recovery provision cycle',
        "['sudo', '-n', '-v']",
        "['sudo', '-n', 'bash', route_script, 'enable']",
    ),
)
if 'forcing a clean provision cycle' in kingdoms_provider:
    fail('recovery logging still claims the now-graceful recovery cycle is forced')

preflight_call = kingdoms_provider.find('if not self.prepare_install():')
first_guest_start = kingdoms_provider.find('if not self._bring_up_router():')
if preflight_call == -1 or first_guest_start == -1 or preflight_call >= first_guest_start:
    fail('Kingdoms install must complete host-network preflight before starting GOAD-ROUTER')

nat_enable = Path('ansible/roles/settings/enable_nat_adapter/tasks/main.yml').read_text()
require_tokens(
    'NAT adapter WinRM-safe transition',
    nat_enable,
    (
        'Start-Sleep -Seconds 5',
        'netsh interface set interface',
        'async: 60',
        'poll: 0',
        'ansible.builtin.meta: reset_connection',
        'ansible.builtin.wait_for_connection:',
        'timeout: 300',
        "if ($adapter.AdminStatus -ne 'Up')",
        'until: nat_adapter_enable_check.rc == 0',
    ),
)
if 'enable_adpter_interface' in nat_enable:
    fail('NAT adapter enable still retries the expected WinRM transport teardown as a task failure')

# A failed first bring-up must no longer hard-power Windows off as the primary
# recovery action. Older Server 2016 boxes have demonstrated a fully booted
# desktop with dead VMware Tools/WSMan after an unconditional halt -f. Require
# the recovery path to call the graceful-stop controller before the bounded
# Vagrant provisioning cycle. Forced halt remains only as the final fallback.
recovery_match = re.search(
    r'(?ms)^    def _recover_failed_windows_vagrant_up\(self, machine\):.*?(?=^    def install\(self\):)',
    kingdoms_provider,
)
if recovery_match is None:
    fail('cannot isolate GOAD Kingdoms failed-bring-up recovery implementation')
recovery = recovery_match.group(0)
if 'self._stop_failed_windows_guest_cleanly(machine)' not in recovery:
    fail('failed-bring-up recovery must invoke graceful Windows shutdown controller')
if "self._run_vagrant_bounded(['up', machine, '--provision'], timeout=600)" not in recovery:
    fail('failed-bring-up recovery must use a bounded Vagrant --provision cycle')

# Check the actual dispatch, rather than banning every Tools override by name.
# A scoped service-reporting repair is legitimate, but failed first-up recovery
# must remain an independent, mandatory decision in install().
provider_class = next(n for n in ast.parse(kingdoms_provider).body
                      if isinstance(n, ast.ClassDef) and n.name == 'GoadKingdomsVmwareProvider')
methods = {n.name: n for n in provider_class.body if isinstance(n, ast.FunctionDef)}

def matches(node, expression):
    return ast.dump(node) == ast.dump(ast.parse(expression, mode='eval').body)

guest_loop = next((n for n in methods['install'].body
                   if isinstance(n, ast.For) and matches(n.iter, 'self.goad_nomad_windows')), None)
if guest_loop is None:
    fail('cannot find the independent Windows install loop')
creation = next((i for i, n in enumerate(guest_loop.body)
                 if isinstance(n, ast.Assign)
                 and any(isinstance(t, ast.Name) and t.id == 'first_up' for t in n.targets)
                 and matches(n.value, "self.command.run_vagrant(['up', machine], self.path)")), -1)
readiness = next((i for i, n in enumerate(guest_loop.body)
                  if isinstance(n, ast.If) and matches(n.test, 'not self._ensure_vmware_tools(machine)')), -1)
dispatch = next((i for i, n in enumerate(guest_loop.body)
                 if isinstance(n, ast.If) and matches(n.test, 'not first_up')), -1)
if not 0 <= creation < readiness < dispatch:
    fail('failed-up recovery must follow creation and Tools readiness independently')
recovery_guard = next((n for n in guest_loop.body[dispatch].body if isinstance(n, ast.If)
                       and matches(n.test, 'not self._recover_failed_windows_vagrant_up(machine)')), None)
if recovery_guard is None or not any(isinstance(n, ast.Return) and matches(n.value, 'False')
                                     for n in recovery_guard.body):
    fail('failed Vagrant recovery must stop installation even if Tools are healthy')
tools_override = methods.get('_ensure_vmware_tools')
if tools_override is not None and any(
        isinstance(n, ast.Call) and matches(n, 'self._recover_failed_windows_vagrant_up(machine)')
        for n in ast.walk(tools_override)):
    fail('failed-up recovery must not be hidden inside VMware Tools readiness')

provisioner = Path('goad/provisioner/ansible/ansible.py').read_text()
for token in ('_prepare_provider_provisioning', '_finalize_provider_provisioning', 'get_playbook_list'):
    if token not in provisioner:
        fail(f'Ansible clean-install lifecycle missing provider hook: {token}')
PY
pass 'GOAD clean-install orchestration + unattended lifecycle contract'

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
printf 'A fresh GOAD/VMware install is wired for unattended sudo continuity, segmented provisioning, WS01 foundation, and all 20 LPE scenarios.\n'
