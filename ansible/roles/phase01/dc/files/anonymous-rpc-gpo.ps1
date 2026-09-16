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
$serverRegistryKey = 'HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters'
$lsaRegistryKey = 'HKLM\System\CurrentControlSet\Control\Lsa'
$desiredPipes = [string[]]@('samr', 'lsarpc')

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
    $gpo = New-GPO -Name $gpoName -Domain $domain -Server $dcFqdn -Comment 'Kingdoms Phase 01 intentionally exposes the anonymous RPC curriculum path while normal null-session shares and general Everyone permissions remain restricted.'
}

function Get-ConfiguredRegistryValue {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$ValueName
    )
    try {
        return Get-GPRegistryValue -Guid $gpo.Id -Domain $domain -Server $dcFqdn -Key $Key -ValueName $ValueName -ErrorAction Stop
    } catch {
        return $null
    }
}

$restrict = Get-ConfiguredRegistryValue -Key $serverRegistryKey -ValueName 'RestrictNullSessAccess'
$pipes = Get-ConfiguredRegistryValue -Key $serverRegistryKey -ValueName 'NullSessionPipes'
$everyoneAnonymous = Get-ConfiguredRegistryValue -Key $lsaRegistryKey -ValueName 'EveryoneIncludesAnonymous'

$restrictChanged = $null -eq $restrict -or [int]$restrict.Value -ne 1
$everyoneChanged = $null -eq $everyoneAnonymous -or [int]$everyoneAnonymous.Value -ne 0
$currentPipes = @()
if ($null -ne $pipes) {
    $currentPipes = @($pipes.Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
$normalizedCurrent = @($currentPipes | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object -Unique)
$normalizedDesired = @($desiredPipes | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
$pipesChanged = $normalizedCurrent.Count -ne $normalizedDesired.Count -or
    @($normalizedDesired | Where-Object { $_ -notin $normalizedCurrent }).Count -ne 0

$inheritance = Get-GPInheritance -Target $targetOu -Domain $domain -Server $dcFqdn
$link = @($inheritance.GpoLinks | Where-Object { $_.GpoId -eq $gpo.Id }) | Select-Object -First 1
$linkChanged = $null -eq $link -or -not [bool]$link.Enabled -or [int]$link.Order -ne 2 -or [bool]$link.Enforced

if ($restrictChanged -or $pipesChanged -or $everyoneChanged -or $linkChanged) {
    $Ansible.Changed = $true
}

if (-not $Ansible.CheckMode) {
    if ($restrictChanged) {
        Set-GPRegistryValue -Guid $gpo.Id -Domain $domain -Server $dcFqdn `
            -Key $serverRegistryKey -ValueName 'RestrictNullSessAccess' -Type DWord -Value 1 | Out-Null
    }
    if ($pipesChanged) {
        Set-GPRegistryValue -Guid $gpo.Id -Domain $domain -Server $dcFqdn `
            -Key $serverRegistryKey -ValueName 'NullSessionPipes' -Type MultiString -Value ([string[]]$desiredPipes) | Out-Null
    }
    if ($everyoneChanged) {
        Set-GPRegistryValue -Guid $gpo.Id -Domain $domain -Server $dcFqdn `
            -Key $lsaRegistryKey -ValueName 'EveryoneIncludesAnonymous' -Type DWord -Value 0 | Out-Null
    }

    if ($null -eq $link) {
        New-GPLink -Guid $gpo.Id -Target $targetOu -Domain $domain -Server $dcFqdn -LinkEnabled Yes -Enforced No -Order 2 | Out-Null
    } elseif ($linkChanged) {
        Set-GPLink -Guid $gpo.Id -Target $targetOu -Domain $domain -Server $dcFqdn -LinkEnabled Yes -Enforced No -Order 2 | Out-Null
    }
}

$Ansible.Result = @{
    gpo = $gpoName
    id = $gpo.Id.ToString()
    target = $targetOu
    link_order = 2
    EveryoneIncludesAnonymous = 0
    RestrictNullSessAccess = 1
    NullSessionPipes = $desiredPipes
}
