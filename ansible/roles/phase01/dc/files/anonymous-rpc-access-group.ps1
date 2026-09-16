[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false

Import-Module ActiveDirectory

$domain = 'north.sevenkingdoms.local'
$dcFqdn = 'winterfell.north.sevenkingdoms.local'
$preWinSid = 'S-1-5-32-554'
$anonymousSid = 'S-1-5-7'

$system = Get-CimInstance Win32_ComputerSystem
if ($system.Name -ine 'WINTERFELL' -or
    $system.Domain -ine $domain -or
    $system.DomainRole -lt 4) {
    throw 'Phase 01 anonymous-RPC compatibility-group provisioning requires WINTERFELL in NORTH.'
}

$group = Get-ADGroup -Identity $preWinSid -Server $dcFqdn -ErrorAction Stop
$members = @(Get-ADGroupMember -Identity $group.DistinguishedName -Server $dcFqdn -ErrorAction Stop)
$anonymousPresent = @($members | Where-Object { $_.SID -and $_.SID.Value -eq $anonymousSid }).Count -gt 0

if (-not $anonymousPresent) {
    $Ansible.Changed = $true
    if (-not $Ansible.CheckMode) {
        # Microsoft documents this built-in group as the compatibility ACL path for
        # anonymous user/group information on domain controllers. net.exe resolves
        # the well-known ANONYMOUS LOGON principal and creates the required group
        # membership without depending on a pre-existing foreignSecurityPrincipal.
        $output = & net.exe localgroup 'Pre-Windows 2000 Compatible Access' 'ANONYMOUS LOGON' /add 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to add ANONYMOUS LOGON to Pre-Windows 2000 Compatible Access: $($output -join ' ')"
        }
    }
}

if (-not $Ansible.CheckMode) {
    $members = @(Get-ADGroupMember -Identity $group.DistinguishedName -Server $dcFqdn -ErrorAction Stop)
    $anonymousPresent = @($members | Where-Object { $_.SID -and $_.SID.Value -eq $anonymousSid }).Count -gt 0
    if (-not $anonymousPresent) {
        throw 'ANONYMOUS LOGON is still missing from Pre-Windows 2000 Compatible Access after provisioning.'
    }
}

$Ansible.Result = @{
    group = $group.Name
    group_sid = $preWinSid
    anonymous_sid = $anonymousSid
    anonymous_member = $anonymousPresent
}
