#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

bash scripts/verify-test-source.sh
pass 'Git source-of-truth gate'

readonly TECHNIQUE_FILES=(
    ansible/roles/windows_lpe/tasks/techniques/unquoted_service_path.yml
    ansible/roles/windows_lpe/tasks/techniques/weak_service_dacl.yml
    ansible/roles/windows_lpe/tasks/techniques/weak_service_binary_permissions.yml
    ansible/roles/windows_lpe/tasks/techniques/weak_service_registry_permissions.yml
    ansible/roles/windows_lpe/tasks/techniques/service_dll_hijacking.yml
    ansible/roles/windows_lpe/tasks/techniques/path_search_order_hijacking.yml
    ansible/roles/windows_lpe/tasks/techniques/scheduled_task_binary_permissions.yml
    ansible/roles/windows_lpe/tasks/techniques/scheduled_task_directory_permissions.yml
    ansible/roles/windows_lpe/tasks/techniques/unattend_credentials.yml
    ansible/roles/windows_lpe/tasks/techniques/powershell_history_credentials.yml
    ansible/roles/windows_lpe/tasks/techniques/hardcoded_application_credentials.yml
    ansible/roles/windows_lpe/tasks/techniques/stored_winlogon_credentials.yml
    ansible/roles/windows_lpe/tasks/techniques/writable_program_directory.yml
    ansible/roles/windows_lpe/tasks/techniques/insecure_service_registry.yml
)

for file in \
    ansible/windows-lpe.yml \
    ansible/roles/windows_lpe/defaults/main.yml \
    ansible/roles/windows_lpe/tasks/main.yml \
    "${TECHNIQUE_FILES[@]}" \
    docs/WINDOWS_LPE_CATALOG.md \
    docs/GOAD_KINGDOMS_MILESTONES.md \
    scripts/apply-windows-lpe-candidates.sh \
    scripts/validate-windows-lpe-unquoted-service-path-runtime.sh \
    scripts/validate-windows-lpe-service-batch-runtime.sh \
    scripts/diagnose-ws01-shutdown.sh
do
    [[ -f "${file}" ]] || fail "missing Windows LPE framework file: ${file}"
done
pass 'required Windows LPE framework and current candidate files'

bash -n scripts/validate-windows-lpe-framework-source.sh
bash -n scripts/apply-windows-lpe-candidates.sh
bash -n scripts/validate-windows-lpe-unquoted-service-path-runtime.sh
bash -n scripts/validate-windows-lpe-service-batch-runtime.sh
bash -n scripts/diagnose-ws01-shutdown.sh
pass 'framework/runtime/helper shell syntax'

python3 - <<'PY'
from pathlib import Path
import re


def fail(message):
    raise SystemExit(message)


def yaml_list(text, key):
    match = re.search(rf'(?m)^{re.escape(key)}:\s*\n((?:  - [^\r\n]+(?:\r?\n|$))+)', text)
    if match is None:
        fail(f'missing YAML list: {key}')
    return [line.strip()[2:].strip() for line in match.group(1).splitlines()]

expected_catalog = [
    'unquoted_service_path', 'weak_service_dacl',
    'weak_service_binary_permissions', 'weak_service_registry_permissions',
    'service_dll_hijacking', 'path_search_order_hijacking',
    'always_install_elevated', 'registry_run_keys', 'writable_startup_folder',
    'scheduled_task_binary_permissions', 'scheduled_task_directory_permissions',
    'unattend_credentials', 'powershell_history_credentials',
    'hardcoded_application_credentials', 'stored_runas_credentials',
    'stored_winlogon_credentials', 'sebackup_privilege',
    'seimpersonate_privilege', 'writable_program_directory',
    'insecure_service_registry',
]

implemented = [
    'unquoted_service_path', 'weak_service_dacl',
    'weak_service_binary_permissions', 'weak_service_registry_permissions',
    'service_dll_hijacking',
]

candidates = [
    'path_search_order_hijacking',
    'scheduled_task_binary_permissions',
    'scheduled_task_directory_permissions',
    'unattend_credentials',
    'powershell_history_credentials',
    'hardcoded_application_credentials',
    'stored_winlogon_credentials',
    'writable_program_directory',
    'insecure_service_registry',
]

markers = {
    'unquoted_service_path': 'WINDOWS_LPE_UNQUOTED_SERVICE_PATH',
    'weak_service_dacl': 'WINDOWS_LPE_WEAK_SERVICE_DACL',
    'weak_service_binary_permissions': 'WINDOWS_LPE_WEAK_SERVICE_BINARY_PERMISSIONS',
    'weak_service_registry_permissions': 'WINDOWS_LPE_WEAK_SERVICE_REGISTRY_PERMISSIONS',
    'service_dll_hijacking': 'WINDOWS_LPE_SERVICE_DLL_HIJACKING',
    'path_search_order_hijacking': 'WINDOWS_LPE_PATH_SEARCH_ORDER_HIJACKING',
    'scheduled_task_binary_permissions': 'WINDOWS_LPE_SCHEDULED_TASK_BINARY_PERMISSIONS',
    'scheduled_task_directory_permissions': 'WINDOWS_LPE_SCHEDULED_TASK_DIRECTORY_PERMISSIONS',
    'unattend_credentials': 'WINDOWS_LPE_UNATTEND_CREDENTIALS',
    'powershell_history_credentials': 'WINDOWS_LPE_POWERSHELL_HISTORY_CREDENTIALS',
    'hardcoded_application_credentials': 'WINDOWS_LPE_HARDCODED_APPLICATION_CREDENTIALS',
    'stored_winlogon_credentials': 'WINDOWS_LPE_STORED_WINLOGON_CREDENTIALS',
    'writable_program_directory': 'WINDOWS_LPE_WRITABLE_PROGRAM_DIRECTORY',
    'insecure_service_registry': 'WINDOWS_LPE_INSECURE_SERVICE_REGISTRY',
}

privilege_evidence_tokens = {
    'unquoted_service_path': 'LocalSystem',
    'weak_service_dacl': 'LocalSystem',
    'weak_service_binary_permissions': 'LocalSystem',
    'weak_service_registry_permissions': 'LocalSystem',
    'service_dll_hijacking': 'LocalSystem',
    'path_search_order_hijacking': 'LocalSystem',
    'scheduled_task_binary_permissions': "UserId 'SYSTEM'",
    'scheduled_task_directory_permissions': "UserId 'SYSTEM'",
    'unattend_credentials': "Group 'Administrators'",
    'powershell_history_credentials': "Group 'Administrators'",
    'hardcoded_application_credentials': "Group 'Administrators'",
    'stored_winlogon_credentials': "Group 'Administrators'",
    'writable_program_directory': 'LocalSystem',
    'insecure_service_registry': 'LocalSystem',
}

defaults = Path('ansible/roles/windows_lpe/defaults/main.yml').read_text()
tasks = Path('ansible/roles/windows_lpe/tasks/main.yml').read_text()
playbook = Path('ansible/windows-lpe.yml').read_text()
catalog_doc = Path('docs/WINDOWS_LPE_CATALOG.md').read_text()
batch_runtime = Path('scripts/validate-windows-lpe-service-batch-runtime.sh').read_text()
single_runtime = Path('scripts/validate-windows-lpe-unquoted-service-path-runtime.sh').read_text()
helper = Path('scripts/apply-windows-lpe-candidates.sh').read_text()

if yaml_list(defaults, 'windows_lpe_catalog') != expected_catalog:
    fail('Windows LPE catalog does not match the 20-technique contract')
if yaml_list(defaults, 'windows_lpe_candidate_techniques') != candidates:
    fail('current Windows LPE candidate set is incorrect')
if yaml_list(defaults, 'windows_lpe_implemented_techniques') != implemented:
    fail('implemented Service Batch 1 set is incorrect')

for profile in ('none', 'service-abuse', 'credential-hunting', 'registry-abuse', 'token-abuse', 'mixed', 'full-lpe'):
    if not re.search(rf'(?m)^  {re.escape(profile)}:', defaults):
        fail(f'missing Windows LPE profile: {profile}')

for token in ('hosts: ws01', 'role: windows_lpe'):
    if token not in playbook:
        fail(f'Windows LPE playbook missing: {token}')

for technique_id in implemented + candidates:
    if f'techniques/{technique_id}.yml' not in tasks:
        fail(f'controller does not dispatch {technique_id}')

for technique_id, marker in markers.items():
    source = Path(f'ansible/roles/windows_lpe/tasks/techniques/{technique_id}.yml').read_text()
    for state in ('APPLIED', 'VULNERABLE', 'RESET', 'CLEAN'):
        if f'{marker}={state}' not in source:
            fail(f'{technique_id} lifecycle marker missing: {state}')
    if privilege_evidence_tokens[technique_id] not in source:
        fail(f'{technique_id} does not define/validate privileged impact')
    for forbidden in ('Set-MpPreference', 'Set-NetFirewallProfile', 'DisableAntiSpyware', 'EnableLUA = 0'):
        if forbidden.lower() in source.lower():
            fail(f'{technique_id} weakens unrelated security controls: {forbidden}')

path_source = Path('ansible/roles/windows_lpe/tasks/techniques/path_search_order_hijacking.yml').read_text()
for token in ('EnvironmentVariableTarget.Machine', 'windows_lpe_path_search_order_hijacking.helper_name'):
    if token not in path_source:
        fail(f'PATH search-order candidate contract missing: {token}')

binary_task = Path('ansible/roles/windows_lpe/tasks/techniques/scheduled_task_binary_permissions.yml').read_text()
for token in ('New-ScheduledTaskTrigger -AtStartup', 'FileSystemRights]::Modify'):
    if token not in binary_task:
        fail(f'scheduled-task binary candidate contract missing: {token}')

directory_task = Path('ansible/roles/windows_lpe/tasks/techniques/scheduled_task_directory_permissions.yml').read_text()
for token in ('DeleteSubdirectoriesAndFiles', 'SetAccessRuleProtection($true, $true)'):
    if token not in directory_task:
        fail(f'scheduled-task directory candidate contract missing: {token}')

credential_contracts = {
    'unattend_credentials': ('<PlainText>true</PlainText>', 'New-LocalUser'),
    'powershell_history_credentials': ('ConsoleHost_history.txt', 'ProfileList'),
    'hardcoded_application_credentials': ('service_password=', 'New-LocalUser'),
    'stored_winlogon_credentials': ('DefaultPassword', 'AutoAdminLogon'),
}
for technique_id, tokens in credential_contracts.items():
    source = Path(f'ansible/roles/windows_lpe/tasks/techniques/{technique_id}.yml').read_text()
    for token in tokens:
        if token not in source:
            fail(f'{technique_id} credential contract missing: {token}')

program_source = Path('ansible/roles/windows_lpe/tasks/techniques/writable_program_directory.yml').read_text()
for token in ('DeleteSubdirectoriesAndFiles', 'CreateFiles', 'SetAccessRuleProtection($true, $true)'):
    if token not in program_source:
        fail(f'writable program directory contract missing: {token}')

registry_source = Path('ansible/roles/windows_lpe/tasks/techniques/insecure_service_registry.yml').read_text()
for token in ('RegistryRights]::SetValue', 'HelperPath', 'Microsoft.Win32'):
    if token not in registry_source:
        fail(f'insecure service registry contract missing: {token}')

for token in ('windows_lpe_candidate_techniques', 'windows_lpe_implemented_techniques', 'windows_lpe_allow_candidate | bool', "windows_lpe_action in ['apply', 'validate', 'reset']"):
    if token not in tasks:
        fail(f'fail-closed controller contract missing: {token}')

for technique_id in implemented:
    if technique_id not in batch_runtime:
        fail(f'Service Batch 1 runtime gate missing: {technique_id}')

for token in ('run_batch apply', 'run_batch validate vulnerable', 'run_batch reset', 'run_batch validate clean', 'require_ws01_ready', 'validate-ws01-runtime.sh', '[READY] Windows LPE service batch live promotion gate passed.'):
    if token not in batch_runtime:
        fail(f'Service Batch 1 promotion contract missing: {token}')

for token in ('run_lpe apply', 'run_lpe validate vulnerable', 'run_lpe reset', 'run_lpe validate clean', '[READY] unquoted_service_path live promotion gate passed.'):
    if token not in single_runtime:
        fail(f'original engine-proof gate regressed: {token}')

for technique_id in expected_catalog:
    if f'`{technique_id}`' not in catalog_doc:
        fail(f'catalog documentation missing technique: {technique_id}')
for technique_id in implemented:
    if not re.search(rf'\| `{re.escape(technique_id)}` \|[^\n]*\| \*\*Implemented\*\* \|', catalog_doc):
        fail(f'catalog does not mark implemented {technique_id}')
for technique_id in candidates:
    if not re.search(rf'\| `{re.escape(technique_id)}` \|[^\n]*\| \*\*Candidate\*\* \|', catalog_doc):
        fail(f'catalog does not mark candidate {technique_id}')

for token in ('windows_lpe_action=apply', 'windows_lpe_allow_candidate=true', 'windows_lpe_techniques'):
    if token not in helper:
        fail(f'candidate apply helper contract missing: {token}')
PY
pass 'implemented Service Batch 1 plus current candidate lifecycle contract'

git diff --check
pass 'Git whitespace check'

printf '\n[READY] GOAD Kingdoms Windows LPE framework source validation passed.\n'
