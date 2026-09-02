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
    docs/WINDOWS_LPE_CATALOG.md \
    docs/GOAD_KINGDOMS_MILESTONES.md
do
    [[ -f "${file}" ]] || fail "missing Windows LPE framework file: ${file}"
done
pass "required Windows LPE framework files"

bash -n scripts/validate-windows-lpe-framework-source.sh
pass "framework validator shell syntax"

python3 - <<'PY'
from pathlib import Path
import re


def fail(message):
    raise SystemExit(message)


def yaml_list(text, key):
    # Parse only the contiguous, two-space-indented YAML sequence directly
    # beneath KEY. Do not use `.` here: this regex runs with multiline matching
    # elsewhere and a dot that spans newlines can greedily consume later
    # comments/profile lists and turn them into fake technique IDs.
    match = re.search(
        rf'(?m)^{re.escape(key)}:[ \t]*\r?\n((?:  - [^\r\n]+\r?\n)+)',
        text,
    )
    if match is None:
        fail(f'missing YAML list: {key}')
    return [
        line.strip()[2:].strip()
        for line in match.group(1).splitlines()
        if line.strip()
    ]


def yaml_empty_list(text, key):
    return re.search(rf'(?m)^{re.escape(key)}:\s*\[\]\s*$', text) is not None


defaults = Path('ansible/roles/windows_lpe/defaults/main.yml').read_text()
tasks = Path('ansible/roles/windows_lpe/tasks/main.yml').read_text()
playbook = Path('ansible/windows-lpe.yml').read_text()
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

if not yaml_empty_list(defaults, 'windows_lpe_implemented_techniques'):
    fail('framework checkpoint must keep windows_lpe_implemented_techniques empty')

for profile in (
    'none', 'service-abuse', 'credential-hunting',
    'registry-abuse', 'token-abuse', 'mixed', 'full-lpe',
):
    if not re.search(rf'(?m)^  {re.escape(profile)}:', defaults):
        fail(f'missing Windows LPE profile: {profile}')

for token in (
    'hosts: ws01',
    'role: windows_lpe',
):
    if token not in playbook:
        fail(f'Windows LPE playbook missing: {token}')

for token in (
    'windows_lpe_action in windows_lpe_supported_actions',
    'windows_lpe_profile in windows_lpe_profiles',
    'difference(windows_lpe_implemented_techniques)',
    "windows_lpe_action in ['apply', 'reset']",
    'No Windows LPE technique implementation exists at this framework checkpoint',
):
    if token not in tasks:
        fail(f'fail-closed Windows LPE controller contract missing: {token}')

for forbidden in (
    'Set-MpPreference -DisableRealtimeMonitoring',
    'DisableAntiSpyware',
    'EnableLUA: 0',
    'Set-NetFirewallProfile -Enabled False',
    'netsh advfirewall set allprofiles state off',
):
    if forbidden.lower() in (defaults + tasks + playbook).lower():
        fail(f'framework checkpoint globally weakens WS01 security: {forbidden}')

if 'WS01 FOUNDATION VALIDATED' not in milestones:
    fail('M2 milestone tracker does not record the validated WS01 foundation')
if '4003f8b41f5344650f82c746b83b2fe8fec32010' not in milestones:
    fail('M2 milestone tracker does not record the validated WS01 source commit')

for technique in expected_catalog:
    if f'`{technique}`' not in catalog_doc:
        fail(f'catalog documentation missing technique: {technique}')

PY
pass "catalog, profiles and fail-closed controller contract"

git diff --check
pass "Git whitespace check"

printf '\n[READY] GOAD Kingdoms Windows LPE framework source validation passed.\n'