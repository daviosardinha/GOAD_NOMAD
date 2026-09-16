[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false

Import-Module ActiveDirectory
Import-Module GroupPolicy

$domain = 'north.sevenkingdoms.local'
$domainDn = 'DC=north,DC=sevenkingdoms,DC=local'
$dcFqdn = 'winterfell.north.sevenkingdoms.local'
$targetOu = 'OU=Domain Controllers,DC=north,DC=sevenkingdoms,DC=local'
$gpoName = 'Kingdoms - Phase 01 - Anonymous RPC Exposure'

$system = Get-CimInstance Win32_ComputerSystem
if ($system.Name -ine 'WINTERFELL' -or
    $system.Domain -ine $domain -or
    $system.DomainRole -lt 4) {
    throw 'Phase 01 anonymous-RPC GPO provisioning requires WINTERFELL in NORTH.'
}

$adDomain = Get-ADDomain -Identity $domain -Server $dcFqdn
if ($adDomain.DistinguishedName -ine $domainDn) {
    throw "Unexpected NORTH domain DN: $($adDomain.DistinguishedName)"
}

$gpo = Get-GPO -Name $gpoName -Domain $domain -Server $dcFqdn -ErrorAction SilentlyContinue
if ($null -eq $gpo) {
    $Ansible.Changed = $true
    if ($Ansible.CheckMode) {
        $Ansible.Result = @{
            gpo = $gpoName
            target = $targetOu
            action = 'would create dedicated Phase 01 anonymous RPC GPO'
        }
        return
    }
    $gpo = New-GPO -Name $gpoName -Domain $domain -Server $dcFqdn -Comment 'Kingdoms Phase 01 intentionally exposes only selected NULL-session RPC paths for the course.'
}

$settings = @(
    @{
        Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa'
        Name = 'RestrictAnonymous'
        Type = 'DWord'
        Value = 0
    },
    @{
        Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa'
        Name = 'RestrictAnonymousSAM'
        Type = 'DWord'
        Value = 0
    },
    @{
        Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa'
        Name = 'EveryoneIncludesAnonymous'
        Type = 'DWord'
        Value = 0
    },
    @{
        Key = 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
        Name = 'RestrictNullSessAccess'
        Type = 'DWord'
        Value = 1
    },
    @{
        Key = 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
        Name = 'NullSessionPipes'
        Type = 'MultiString'
        Value = @('samr', 'lsarpc')
    }
)

function Test-PolicyValue {
    param(
        $Current,
        [hashtable]$Desired
    )

    if ($null -eq $Current) {
        return $false
    }
    if ([string]$Current.Type -ine [string]$Desired.Type) {
        return $false
    }

    if ($Desired.Type -eq 'MultiString') {
        $actual = @($Current.Value)
        $wanted = @($Desired.Value)
        if ($actual.Count -ne $wanted.Count) {
            return $false
        }
        for ($i = 0; $i -lt $wanted.Count; $i++) {
            if ([string]$actual[$i] -cne [string]$wanted[$i]) {
                return $false
            }
        }
        return $true
    }

    return [int64]$Current.Value -eq [int64]$Desired.Value
}

foreach ($setting in $settings) {
    $current = Get-GPRegistryValue -Guid $gpo.Id -Key $setting.Key -ValueName $setting.Name `
        -Domain $domain -Server $dcFqdn -ErrorAction SilentlyContinue
    if (-not (Test-PolicyValue -Current $current -Desired $setting)) {
        $Ansible.Changed = $true
        if (-not $Ansible.CheckMode) {
            Set-GPRegistryValue -Guid $gpo.Id -Key $setting.Key -ValueName $setting.Name `
                -Type $setting.Type -Value $setting.Value -Domain $domain -Server $dcFqdn | Out-Null
        }
    }
}

$inheritance = Get-GPInheritance -Target $targetOu -Domain $domain -Server $dcFqdn
$link = @($inheritance.GpoLinks | Where-Object { $_.GpoId -eq $gpo.Id }) | Select-Object -First 1
$linkChanged = $null -eq $link -or -not [bool]$link.Enabled -or [int]$link.Order -ne 2 -or [bool]$link.Enforced
if ($linkChanged) {
    $Ansible.Changed = $true
    if (-not $Ansible.CheckMode) {
        if ($null -eq $link) {
            New-GPLink -Guid $gpo.Id -Target $targetOu -Domain $domain -Server $dcFqdn `
                -LinkEnabled Yes -Enforced No -Order 2 | Out-Null
        } else {
            Set-GPLink -Guid $gpo.Id -Target $targetOu -Domain $domain -Server $dcFqdn `
                -LinkEnabled Yes -Enforced No -Order 2 | Out-Null
        }
    }
}

$Ansible.Result = @{
    gpo = $gpoName
    id = $gpo.Id.ToString()
    target = $targetOu
    link_order = 2
    restrict_null_session_access = 1
    null_session_pipes = @('samr', 'lsarpc')
    restrict_anonymous = 0
    restrict_anonymous_sam = 0
    everyone_includes_anonymous = 0
}
