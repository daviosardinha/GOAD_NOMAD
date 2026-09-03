#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

bash scripts/verify-test-source.sh
pass 'Git source-of-truth gate'

readonly REQUIRED_FILES=(
    ansible/windows-lpe.yml
    ansible/roles/windows_lpe/defaults/main.yml
    ansible/roles/windows_lpe/tasks/main.yml
    ansible/roles/windows_lpe/tasks/techniques/stored_runas_credentials.yml
    ansible/roles/windows_lpe/files/stored_runas/10_core.ps1
    ansible/roles/windows_lpe/files/stored_runas/20_validation.ps1
    ansible/roles/windows_lpe/files/stored_runas/30_lifecycle.ps1
    docs/WINDOWS_LPE_CATALOG.md
    docs/GOAD_KINGDOMS_MILESTONES.md
    scripts/apply-windows-lpe-candidates.sh
    scripts/validate-windows-lpe-unquoted-service-path-runtime.sh
    scripts/validate-windows-lpe-service-batch-runtime.sh
    scripts/diagnose-ws01-shutdown.sh
)
for file in "${REQUIRED_FILES[@]}"; do
    [[ -f "${file}" ]] || fail "missing Windows LPE framework file: ${file}"
done
pass 'required Windows LPE framework and RunAs runtime files'

bash -n scripts/validate-windows-lpe-framework-source.sh
bash -n scripts/apply-windows-lpe-candidates.sh
bash -n scripts/validate-windows-lpe-unquoted-service-path-runtime.sh
bash -n scripts/validate-windows-lpe-service-batch-runtime.sh
bash -n scripts/diagnose-ws01-shutdown.sh
pass 'framework/runtime/helper shell syntax'

readonly ANSIBLE_PLAYBOOK="${HOME}/.goad/.venv/bin/ansible-playbook"
[[ -x "${ANSIBLE_PLAYBOOK}" ]] || fail "GOAD Ansible runtime missing: ${ANSIBLE_PLAYBOOK}"

ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg" \
    "${ANSIBLE_PLAYBOOK}" -i 'ws01,' "${ROOT}/ansible/windows-lpe.yml" --syntax-check >/dev/null
pass 'top-level Windows LPE playbook syntax check'

# include_tasks is dynamic and normal --syntax-check does not parse its targets.
# Force every technique file through Ansible using static import_tasks.
static_playbook="$(mktemp "${ROOT}/ansible/.windows-lpe-static-syntax.XXXXXX.yml")"
cleanup_static() { rm -f "${static_playbook}"; }
trap cleanup_static EXIT
{
    printf '%s\n' '---'
    printf '%s\n' '- name: Static parse every Windows LPE technique'
    printf '%s\n' '  hosts: ws01'
    printf '%s\n' '  gather_facts: false'
    printf '%s\n' '  tasks:'
    for technique_file in "${ROOT}"/ansible/roles/windows_lpe/tasks/techniques/*.yml; do
        technique_name="$(basename "${technique_file}")"
        printf '    - name: Static parse %s\n' "${technique_name}"
        printf '      ansible.builtin.import_tasks: roles/windows_lpe/tasks/techniques/%s\n' "${technique_name}"
    done
} >"${static_playbook}"
ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg" \
    "${ANSIBLE_PLAYBOOK}" -i 'ws01,' "${static_playbook}" --syntax-check >/dev/null
cleanup_static
trap - EXIT
pass 'static Ansible/YAML parse of every Windows LPE technique file'

python3 - <<'PY'
from pathlib import Path
import base64
import re


def fail(message):
    raise SystemExit(message)


def yaml_list(text, key):
    match = re.search(rf'(?m)^{re.escape(key)}:\s*\n((?:  - [^\r\n]+(?:\r?\n|$))+)', text)
    if match is None:
        fail(f'missing YAML list: {key}')
    return [line.strip()[2:].strip() for line in match.group(1).splitlines()]

expected_catalog = [
    'unquoted_service_path', 'weak_service_dacl', 'weak_service_binary_permissions',
    'weak_service_registry_permissions', 'service_dll_hijacking', 'path_search_order_hijacking',
    'always_install_elevated', 'registry_run_keys', 'writable_startup_folder',
    'scheduled_task_binary_permissions', 'scheduled_task_directory_permissions',
    'unattend_credentials', 'powershell_history_credentials', 'hardcoded_application_credentials',
    'stored_runas_credentials', 'stored_winlogon_credentials', 'sebackup_privilege',
    'seimpersonate_privilege', 'writable_program_directory', 'insecure_service_registry',
]
implemented_service_batch = [
    'unquoted_service_path', 'weak_service_dacl', 'weak_service_binary_permissions',
    'weak_service_registry_permissions', 'service_dll_hijacking',
]

defaults = Path('ansible/roles/windows_lpe/defaults/main.yml').read_text()
tasks = Path('ansible/roles/windows_lpe/tasks/main.yml').read_text()
playbook = Path('ansible/windows-lpe.yml').read_text()
catalog_doc = Path('docs/WINDOWS_LPE_CATALOG.md').read_text()
batch_runtime = Path('scripts/validate-windows-lpe-service-batch-runtime.sh').read_text()
single_runtime = Path('scripts/validate-windows-lpe-unquoted-service-path-runtime.sh').read_text()
helper = Path('scripts/apply-windows-lpe-candidates.sh').read_text()

catalog = yaml_list(defaults, 'windows_lpe_catalog')
candidates = yaml_list(defaults, 'windows_lpe_candidate_techniques')
implemented = yaml_list(defaults, 'windows_lpe_implemented_techniques')
available = implemented + candidates

if catalog != expected_catalog:
    fail('Windows LPE catalog does not match the 20-technique contract')
if implemented != implemented_service_batch:
    fail('implemented Service Batch 1 set is incorrect')
if len(set(candidates)) != len(candidates):
    fail('duplicate Windows LPE candidate technique')
if set(implemented) & set(candidates):
    fail('a Windows LPE technique is both implemented and candidate')
if set(available) - set(catalog):
    fail('available Windows LPE techniques contain unknown catalog IDs')

for profile in ('none', 'service-abuse', 'credential-hunting', 'registry-abuse', 'token-abuse', 'mixed', 'full-lpe'):
    if not re.search(rf'(?m)^  {re.escape(profile)}:', defaults):
        fail(f'missing Windows LPE profile: {profile}')
for token in ('hosts: ws01', 'role: windows_lpe'):
    if token not in playbook:
        fail(f'Windows LPE playbook missing: {token}')

for technique_id in available:
    source_path = Path(f'ansible/roles/windows_lpe/tasks/techniques/{technique_id}.yml')
    if not source_path.is_file():
        fail(f'missing source implementation for {technique_id}')
    if f'techniques/{technique_id}.yml' not in tasks:
        fail(f'controller does not dispatch {technique_id}')
    source = source_path.read_text()
    marker = 'WINDOWS_LPE_' + technique_id.upper()
    for state in ('APPLIED', 'VULNERABLE', 'RESET', 'CLEAN'):
        # stored_runas markers live in its external PowerShell runtime.
        if technique_id == 'stored_runas_credentials':
            continue
        if f'{marker}={state}' not in source:
            fail(f'{technique_id} lifecycle marker missing: {state}')
    for forbidden in ('Set-MpPreference', 'Set-NetFirewallProfile', 'DisableAntiSpyware', 'EnableLUA = 0'):
        if forbidden.lower() in source.lower():
            fail(f'{technique_id} weakens unrelated security controls: {forbidden}')

contracts = {
    'path_search_order_hijacking': ('EnvironmentVariableTarget.Machine', 'helper_name'),
    'scheduled_task_binary_permissions': ('New-ScheduledTaskTrigger -AtStartup', 'FileSystemRights]::Modify'),
    'scheduled_task_directory_permissions': ('DeleteSubdirectoriesAndFiles', 'SetAccessRuleProtection($true, $true)'),
    'unattend_credentials': ('<PlainText>true</PlainText>', 'New-LocalUser'),
    'powershell_history_credentials': ('ConsoleHost_history.txt', 'ProfileList'),
    'hardcoded_application_credentials': ('service_password=', 'New-LocalUser'),
    'stored_winlogon_credentials': ('DefaultPassword', 'AutoAdminLogon'),
    'writable_program_directory': ('DeleteSubdirectoriesAndFiles', 'CreateFiles', 'SetAccessRuleProtection($true, $true)'),
    'insecure_service_registry': ('RegistryRights]::SetValue', 'HelperPath', 'Microsoft.Win32'),
    'sebackup_privilege': ('SeBackupPrivilege', 'LsaAddAccountRights', 'LsaRemoveAccountRights', 'preexisting'),
    'seimpersonate_privilege': ('SeImpersonatePrivilege', 'LsaAddAccountRights', 'LsaRemoveAccountRights', 'preexisting'),
}
for technique_id, tokens in contracts.items():
    if technique_id not in available:
        continue
    source = Path(f'ansible/roles/windows_lpe/tasks/techniques/{technique_id}.yml').read_text()
    for token in tokens:
        if token not in source:
            fail(f'{technique_id} contract missing: {token}')

if 'stored_runas_credentials' in available:
    wrapper = Path('ansible/roles/windows_lpe/tasks/techniques/stored_runas_credentials.yml').read_text()
    part_paths = [
        Path('ansible/roles/windows_lpe/files/stored_runas/10_core.ps1'),
        Path('ansible/roles/windows_lpe/files/stored_runas/20_validation.ps1'),
        Path('ansible/roles/windows_lpe/files/stored_runas/30_lifecycle.ps1'),
    ]
    runtime = ''.join(path.read_text() for path in part_paths)
    for token in ('sensitive_parameters:', 'OwnerCredential', 'RunAsCredential', '10_core.ps1', '20_validation.ps1', '30_lifecycle.ps1'):
        if token not in wrapper:
            fail(f'stored_runas_credentials wrapper contract missing: {token}')
    for token in ('Domain:interactive=', 'RUNAS_SAVECRED_OK', 'ProcessStartInfo', 'WINDOWS_LPE_STORED_RUNAS_CREDENTIALS=APPLIED', 'WINDOWS_LPE_STORED_RUNAS_CREDENTIALS=VULNERABLE', 'WINDOWS_LPE_STORED_RUNAS_CREDENTIALS=RESET', 'WINDOWS_LPE_STORED_RUNAS_CREDENTIALS=CLEAN'):
        if token not in runtime:
            fail(f'stored_runas_credentials runtime contract missing: {token}')
    if re.search(r'(?m)^\s*elif\b', runtime):
        fail('stored_runas_credentials contains non-PowerShell elif syntax')
    match = re.search(r"\$CredentialInteropB64\s*=\s*'([A-Za-z0-9+/=]+)'", runtime)
    if match is None:
        fail('stored_runas_credentials Base64 interop payload missing')
    try:
        interop = base64.b64decode(match.group(1), validate=True).decode('utf-8')
    except Exception as exc:
        fail(f'stored_runas_credentials Base64 interop payload invalid: {exc}')
    for token in ('credential.Flags = 8196', 'Encoding.ASCII.GetBytes(password)', 'credential.Persist = 3', 'CredWriteW', 'CredDeleteW'):
        if token not in interop:
            fail(f'stored_runas_credentials decoded interop contract missing: {token}')
    if "credential_target: 'WS01\\kingdom.runas'" not in defaults:
        fail('stored_runas_credentials target must be WS01\\kingdom.runas')

for token in ('windows_lpe_candidate_techniques', 'windows_lpe_implemented_techniques', 'windows_lpe_allow_candidate | bool', "windows_lpe_action in ['apply', 'validate', 'reset']"):
    if token not in tasks:
        fail(f'fail-closed controller contract missing: {token}')
for technique_id in implemented_service_batch:
    if technique_id not in batch_runtime:
        fail(f'Service Batch 1 runtime gate missing: {technique_id}')
for token in ('run_batch apply', 'run_batch validate vulnerable', 'run_batch reset', 'run_batch validate clean', 'require_ws01_ready', 'validate-ws01-runtime.sh'):
    if token not in batch_runtime:
        fail(f'Service Batch 1 promotion contract missing: {token}')
for token in ('run_lpe apply', 'run_lpe validate vulnerable', 'run_lpe reset', 'run_lpe validate clean'):
    if token not in single_runtime:
        fail(f'original engine-proof gate regressed: {token}')
for technique_id in expected_catalog:
    if f'`{technique_id}`' not in catalog_doc:
        fail(f'catalog documentation missing technique: {technique_id}')
for token in ('windows_lpe_action=apply', 'windows_lpe_allow_candidate=true', 'windows_lpe_techniques'):
    if token not in helper:
        fail(f'candidate apply helper contract missing: {token}')
PY
pass 'dynamic Windows LPE candidate and stored RunAs source contract'

if command -v pwsh >/dev/null 2>&1; then
    runas_combined="$(mktemp /tmp/goad-stored-runas.XXXXXX.ps1)"
    cat ansible/roles/windows_lpe/files/stored_runas/10_core.ps1 \
        ansible/roles/windows_lpe/files/stored_runas/20_validation.ps1 \
        ansible/roles/windows_lpe/files/stored_runas/30_lifecycle.ps1 >"${runas_combined}"
    pwsh -NoProfile -NonInteractive -Command \
        '$errors=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($args[0],[ref]$null,[ref]$errors); if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }' \
        "${runas_combined}" >/dev/null
    rm -f "${runas_combined}"
    pass 'stored RunAs PowerShell parser check'
else
    printf '[INFO] pwsh not installed on controller; live win_powershell parser remains the runtime authority\n'
fi

git diff --check
pass 'Git whitespace check'

printf '\n[READY] GOAD Kingdoms Windows LPE framework source validation passed.\n'
