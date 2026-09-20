)

member_health = Path('ansible/roles/kingdoms_health/member/tasks/main.yml').read_text()
require_tokens(
    'Kingdoms member health contract',
    member_health,
    (
        'Test-ComputerSecureChannel',
        'Reset-ComputerMachinePassword',
        'nltest.exe',
        'Resolve-DnsName',
        'w32tm.exe',
        'AllowRepair',
        'DomainController',
        'Wait-DomainDiscovery',
        'Invoke-Nltest',
        'KINGDOMS_MEMBER_DCLOCATOR_RETRY',
        '-Server $DomainController',
    ),
)

dc_health = Path('ansible/roles/kingdoms_health/dc/tasks/main.yml').read_text()
require_tokens(
    'Kingdoms domain controller health contract',
    dc_health,
    (
        "'NTDS', 'DNS', 'ADWS', 'Netlogon', 'Kdc', 'W32Time'",
        "'SYSVOL', 'NETLOGON'",
        'Get-ADDomain',
        'Resolve-DnsName',
        'nltest.exe',
    ),
)
if 'Reset-ComputerMachinePassword' in dc_health:
    fail('domain controller health gate must not auto-repair machine trust')
if 'Assert-DomainDiscovery' in member_health:
    fail('member health must not hard-fail on a single DC Locator miss before trust evaluation')
if member_health.index('$discoveryHealthy = Wait-DomainDiscovery') > member_health.index('$trustHealthy = Test-DirectSecureChannel'):
    fail('member health must record bounded locator state before evaluating trust independently')
if '-Server $DomainController' not in member_health:
    fail('member trust validation/repair must pin the known domain controller')

for label, health_script in (
    ('domain controller health contract', dc_health),
    ('member health contract', member_health),
):
    if '$DomainName:' in health_script:
        fail(f'{label} contains unsafe PowerShell interpolation before colon')

if '${DomainName}:' not in dc_health:
    fail('domain controller health contract must delimit DomainName before colon in PowerShell strings')

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

provider_inventory = Path('ad/GOAD/providers/vmware/inventory').read_text().splitlines()
ws01_lines = [
    line.strip()
    for line in provider_inventory
    if re.match(r'^\s*ws01(?:\s|$)', line)