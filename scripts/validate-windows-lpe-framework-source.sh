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

bash scripts/verify-test-source.sh
pass 'Git source-of-truth gate'

readonly TECHNIQUE_FILES=(
    ansible/roles/windows_lpe/tasks/techniques/unquoted_service_path.yml
    ansible/roles/windows_lpe/tasks/techniques/weak_service_dacl.yml
    ansible/roles/windows_lpe/tasks/techniques/weak_service_binary_permissions.yml
    ansible/roles/windows_lpe/tasks/techniques/weak_service_registry_permissions.yml
    ansible/roles/windows_lpe/tasks/techniques/service_dll_hijacking.yml
)

for file in \
    ansible/windows-lpe.yml \
    ansible/roles/windows_lpe/defaults/main.yml \
    ansible/roles/windows_lpe/tasks/main.yml \
    "${TECHNIQUE_FILES[@]}" \
    docs/WINDOWS_LPE_CATALOG.md \
    docs/GOAD_KINGDOMS_MILESTONES.md \
    scripts/validate-windows-lpe-unquoted-service-path-runtime.sh \
    scripts/validate-windows-lpe-service-batch-runtime.sh \
    scripts/diagnose-ws01-shutdown.sh
do
    [[ -f "${file}" ]] || fail "missing Windows LPE framework file: ${file}"
done
pass 'required Windows LPE framework and service-batch files'

bash -n scripts/validate-windows-lpe-framework-source.sh
bash -n scripts/validate-windows-lpe-unquoted-service-path-runtime.sh
bash -n scripts/validate-windows-lpe-service-batch-runtime.sh
bash -n scripts/diagnose-ws01-shutdown.sh
pass 'framework/runtime/diagnostic shell syntax'

python3 - <<'PY'
from pathlib import Path
import re


def fail(message):
    raise SystemExit(message)


def yaml_list(text, key):
    match = re.search(
        rf'(?m)^{re.escape(key)}:\s*\n((?:  - [^\r\n]+(?:\r?\n|$))+)',
        text,
    )
    if match is None:
        fail(f'missing YAML list: {key}')
    return [line.strip()[2:].strip() for line in match.group(1).splitlines()]


expected_catalog = [
    'unquoted_service_path',
    'weak_service_dacl',
    'weak_service_binary_permissions',
    'weak_service_registry_permissions',
    'service_dll_hijacking',
    'path_search_order_hijacking',
    'always_install_elevated',
    'registry_run_keys',
    'writable_startup_folder',
    'scheduled_task_binary_permissions',
    'scheduled_task_directory_permissions',
    'unattend_credentials',
    'powershell_history_credentials',
    'hardcoded_application_credentials',
    'stored_runas_credentials',
    'stored_winlogon_credentials',
    'sebackup_privilege',
    'seimpersonate_privilege',
    'writable_program_directory',
    'insecure_service_registry',
]

service_batch = [
    'unquoted_service_path',
    'weak_service_dacl',
    'weak_service_binary_permissions',
    'weak_service_registry_permissions',
    'service_dll_hijacking',
]

candidates_expected = service_batch[1:]
implemented_expected = ['unquoted_service_path']

defaults = Path('ansible/roles/windows_lpe/defaults/main.yml').read_text()
tasks = Path('ansible/roles/windows_lpe/tasks/main.yml').read_text()
playbook = Path('ansible/windows-lpe.yml').read_text()
catalog_doc = Path('docs/WINDOWS_LPE_CATALOG.md').read_text()
batch_runtime = Path('scripts/validate-windows-lpe-service-batch-runtime.sh').read_text()
single_runtime = Path('scripts/validate-windows-lpe-unquoted-service-path-runtime.sh').read_text()

if yaml_list(defaults, 'windows_lpe_catalog') != expected_catalog:
    fail('Windows LPE catalog does not match the 20-technique contract')
if yaml_list(defaults, 'windows_lpe_candidate_techniques') != candidates_expected:
    fail('service batch candidate set is incorrect')
if yaml_list(defaults, 'windows_lpe_implemented_techniques') != implemented_expected:
    fail('unquoted_service_path was not promoted exactly once')

for profile in (
    'none', 'service-abuse', 'credential-hunting',
    'registry-abuse', 'token-abuse', 'mixed', 'full-lpe',
):
    if not re.search(rf'(?m)^  {re.escape(profile)}:', defaults):
        fail(f'missing Windows LPE profile: {profile}')

for token in ('hosts: ws01', 'role: windows_lpe'):
    if token not in playbook:
        fail(f'Windows LPE playbook missing: {token}')

for technique_id in service_batch:
    include_token = f'techniques/{technique_id}.yml'
    if include_token not in tasks:
        fail(f'controller does not dispatch {technique_id}')

marker_contracts = {
    'unquoted_service_path': 'WINDOWS_LPE_UNQUOTED_SERVICE_PATH',
    'weak_service_dacl': 'WINDOWS_LPE_WEAK_SERVICE_DACL',
    'weak_service_binary_permissions': 'WINDOWS_LPE_WEAK_SERVICE_BINARY_PERMISSIONS',
    'weak_service_registry_permissions': 'WINDOWS_LPE_WEAK_SERVICE_REGISTRY_PERMISSIONS',
    'service_dll_hijacking': 'WINDOWS_LPE_SERVICE_DLL_HIJACKING',
}

for technique_id, marker in marker_contracts.items():
    source = Path(f'ansible/roles/windows_lpe/tasks/techniques/{technique_id}.yml').read_text()
    for state in ('APPLIED', 'VULNERABLE', 'RESET', 'CLEAN'):
        token = f'{marker}={state}'
        if token not in source:
            fail(f'{technique_id} lifecycle marker missing: {token}')
    if 'LocalSystem' not in source:
        fail(f'{technique_id} does not validate a privileged service identity')
    for forbidden in (
        'Set-MpPreference',
        'Set-NetFirewallProfile',
        'DisableAntiSpyware',
        'EnableLUA = 0',
    ):
        if forbidden.lower() in source.lower():
            fail(f'{technique_id} weakens unrelated security controls: {forbidden}')

for token in (
    'windows_lpe_candidate_techniques',
    'windows_lpe_implemented_techniques',
    'windows_lpe_allow_candidate | bool',
    "windows_lpe_action in ['apply', 'validate', 'reset']",
):
    if token not in tasks:
        fail(f'fail-closed controller contract missing: {token}')

for technique_id in service_batch:
    if technique_id not in batch_runtime:
        fail(f'service batch runtime gate missing: {technique_id}')

for token in (
    'run_batch apply',
    'run_batch validate vulnerable',
    'run_batch reset',
    'run_batch validate clean',
    'require_ws01_ready',
    'validate-ws01-runtime.sh',
    '[READY] Windows LPE service batch live promotion gate passed.',
):
    if token not in batch_runtime:
        fail(f'service batch promotion contract missing: {token}')

for token in (
    'run_lpe apply',
    'run_lpe validate vulnerable',
    'run_lpe reset',
    'run_lpe validate clean',
    '[READY] unquoted_service_path live promotion gate passed.',
):
    if token not in single_runtime:
        fail(f'original unquoted-service proof gate regressed: {token}')

for technique_id in expected_catalog:
    if f'`{technique_id}`' not in catalog_doc:
        fail(f'catalog documentation missing technique: {technique_id}')

if '| `unquoted_service_path` | Services | **Implemented** |' not in catalog_doc:
    fail('catalog does not record unquoted_service_path promotion')
for technique_id in candidates_expected:
    if not re.search(rf'\| `{re.escape(technique_id)}` \|[^\n]*\| \*\*Candidate\*\* \|', catalog_doc):
        fail(f'catalog does not mark {technique_id} as Candidate')

if 'windows_lpe_allow_candidate=true' not in catalog_doc:
    fail('catalog does not document explicit candidate opt-in')
if 'service batch live promotion gate' not in catalog_doc.lower():
    fail('catalog does not document the service batch promotion lifecycle')
PY
pass 'promotion, service-batch lifecycle and fail-closed controller contract'

git diff --check
pass 'Git whitespace check'

printf '\n[READY] GOAD Kingdoms Windows LPE framework source validation passed.\n'
