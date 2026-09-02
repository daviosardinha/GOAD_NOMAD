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
pass "Git source-of-truth gate"

for file in \
    ansible/windows-lpe.yml \
    ansible/roles/windows_lpe/defaults/main.yml \
    ansible/roles/windows_lpe/tasks/main.yml \
    ansible/roles/windows_lpe/tasks/techniques/unquoted_service_path.yml \
    docs/WINDOWS_LPE_CATALOG.md \
    docs/GOAD_KINGDOMS_MILESTONES.md \
    scripts/validate-windows-lpe-unquoted-service-path-runtime.sh \
    scripts/diagnose-ws01-shutdown.sh
do
    [[ -f "${file}" ]] || fail "missing Windows LPE framework file: ${file}"
done
pass "required Windows LPE framework files"

bash -n scripts/validate-windows-lpe-framework-source.sh
bash -n scripts/validate-windows-lpe-unquoted-service-path-runtime.sh
bash -n scripts/diagnose-ws01-shutdown.sh
pass "framework/runtime/diagnostic shell syntax"

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


def yaml_empty_list(text, key):
    return re.search(rf'(?m)^{re.escape(key)}:\s*\[\]\s*$', text) is not None


defaults = Path('ansible/roles/windows_lpe/defaults/main.yml').read_text()
tasks = Path('ansible/roles/windows_lpe/tasks/main.yml').read_text()
technique = Path('ansible/roles/windows_lpe/tasks/techniques/unquoted_service_path.yml').read_text()
playbook = Path('ansible/windows-lpe.yml').read_text()
runtime_gate = Path('scripts/validate-windows-lpe-unquoted-service-path-runtime.sh').read_text()
shutdown_diag = Path('scripts/diagnose-ws01-shutdown.sh').read_text()
catalog_doc = Path('docs/WINDOWS_LPE_CATALOG.md').read_text()
milestones = Path('docs/GOAD_KINGDOMS_MILESTONES.md').read_text()

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

catalog = yaml_list(defaults, 'windows_lpe_catalog')
if catalog != expected_catalog:
    fail(f'Windows LPE catalog mismatch: {catalog!r}')

candidates = yaml_list(defaults, 'windows_lpe_candidate_techniques')
if candidates != ['unquoted_service_path']:
    fail(f'unexpected Windows LPE candidate set: {candidates!r}')

if not yaml_empty_list(defaults, 'windows_lpe_implemented_techniques'):
    fail('candidate checkpoint must not promote any technique to implemented before live re-apply validation')

for profile in (
    'none', 'service-abuse', 'credential-hunting',
    'registry-abuse', 'token-abuse', 'mixed', 'full-lpe',
):
    if not re.search(rf'(?m)^  {re.escape(profile)}:', defaults):
        fail(f'missing Windows LPE profile: {profile}')

for token in ('hosts: ws01', 'role: windows_lpe'):
    if token not in playbook:
        fail(f'Windows LPE playbook missing: {token}')

for token in (
    'windows_lpe_action in windows_lpe_supported_actions',
    'windows_lpe_profile in windows_lpe_profiles',
    'windows_lpe_validate_state in windows_lpe_supported_validate_states',
    'windows_lpe_techniques | difference(windows_lpe_catalog)',
    'windows_lpe_candidate_techniques',
    'windows_lpe_allow_candidate | bool',
    "windows_lpe_action in ['apply', 'validate', 'reset']",
    'techniques/unquoted_service_path.yml',
):
    if token not in tasks:
        fail(f'fail-closed Windows LPE controller contract missing: {token}')

for token in (
    'windows_lpe_action: status',
    'windows_lpe_validate_state: vulnerable',
    'windows_lpe_allow_candidate: false',
    'KingdomUpdaterSvc',
    "root: 'C:\\Kingdom LPE'",
    "writable_candidate: 'C:\\Kingdom LPE\\Unquoted.exe'",
):
    if token not in defaults:
        fail(f'unquoted service path defaults contract missing: {token}')

for token in (
    'WINDOWS_LPE_UNQUOTED_SERVICE_PATH=APPLIED',
    'WINDOWS_LPE_UNQUOTED_SERVICE_PATH=VULNERABLE',
    'WINDOWS_LPE_UNQUOTED_SERVICE_PATH=RESET',
    'WINDOWS_LPE_UNQUOTED_SERVICE_PATH=CLEAN',
    'LocalSystem',
    'StartupType Automatic',
    'InheritanceFlags]::None',
    'technique collision detected',
):
    if token not in technique:
        fail(f'unquoted service path lifecycle contract missing: {token}')

if technique.count('S-1-5-32-545') < 2:
    fail('unquoted service path source does not validate BUILTIN\\Users by SID')
if 'Set-MpPreference' in technique or 'Set-NetFirewallProfile' in technique:
    fail('unquoted service path candidate weakens unrelated endpoint security controls')

for token in (
    'validate-ws01-runtime.sh',
    'windows_lpe_action=${action}',
    'windows_lpe_allow_candidate=true',
    'unquoted_service_path',
    'run_lpe apply',
    'run_lpe validate vulnerable',
    'run_lpe reset',
    'run_lpe validate clean',
    'require_ws01_ready',
    'dump_ws01_evidence',
    'diagnose-ws01-shutdown.sh',
    '[READY] unquoted_service_path live promotion gate passed.',
):
    if token not in runtime_gate:
        fail(f'unquoted service path runtime promotion gate missing: {token}')

for token in (
    'Id=1074,6006,6008,41',
    'SoftwareLicensingProduct',
    'GracePeriodRemaining',
    'starting only WS01 without provisioning',
    'vmrun -T ws start',
):
    if token not in shutdown_diag:
        fail(f'WS01 shutdown diagnostic contract missing: {token}')

for forbidden in (
    'Set-MpPreference -DisableRealtimeMonitoring',
    'DisableAntiSpyware',
    'EnableLUA: 0',
    'Set-NetFirewallProfile -Enabled False',
    'netsh advfirewall set allprofiles state off',
):
    if forbidden.lower() in (defaults + tasks + technique + playbook).lower():
        fail(f'Windows LPE framework globally weakens WS01 security: {forbidden}')

if 'WS01 FOUNDATION VALIDATED' not in milestones:
    fail('M2 milestone tracker does not record the validated WS01 foundation')
if '4003f8b41f5344650f82c746b83b2fe8fec32010' not in milestones:
    fail('M2 milestone tracker does not record the validated WS01 source commit')

for technique_id in expected_catalog:
    if f'`{technique_id}`' not in catalog_doc:
        fail(f'catalog documentation missing technique: {technique_id}')

if '| `unquoted_service_path` | Services | **Candidate** |' not in catalog_doc:
    fail('catalog does not mark unquoted_service_path as Candidate')
if 'C:\\Kingdom LPE\\Unquoted.exe' not in catalog_doc:
    fail('catalog does not document the intended writable ambiguous candidate')
if 'windows_lpe_allow_candidate=true' not in catalog_doc:
    fail('catalog does not document explicit candidate opt-in')

PY
pass "catalog, candidate lifecycle, power-loss diagnostics and fail-closed controller contract"

git diff --check
pass "Git whitespace check"

printf '\n[READY] GOAD Kingdoms Windows LPE framework source validation passed.\n'