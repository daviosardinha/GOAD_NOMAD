# Read-only directory evidence, executed on WINTERFELL using existing management.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.Name -ine 'WINTERFELL' -or $cs.Domain -ine 'north.sevenkingdoms.local') {
    throw 'Directory evidence must be collected on WINTERFELL in NORTH'
}
$names = @('hodor','brandon.stark','jon.snow','samwell.tarly','rickon.stark','robb.stark')
$users = @{}
foreach ($name in $names) {
    # Resolve the account first: tokenGroups is computed and requires a BASE
    # search on its distinguished name, not the username-resolution search.
    $resolved = Get-ADUser -Identity $name -Server $cs.Name
    $matches = @(Get-ADUser -LDAPFilter '(objectClass=user)' `
        -SearchBase $resolved.DistinguishedName -SearchScope Base `
        -Server $cs.Name -Properties tokenGroups,Enabled)
    if ($matches.Count -ne 1) { throw "Expected one directory object for $name" }
    $user = $matches[0]
    if ($user.SID.Value -ne $resolved.SID.Value) { throw "Directory identity changed for $name" }
    if (-not $user.Enabled) { throw "Disabled account cannot validate RDP policy: $name" }
    $tokens = @($user.SID.Value)
    foreach ($bytes in $user.tokenGroups) {
        $tokens += (New-Object System.Security.Principal.SecurityIdentifier($bytes, 0)).Value
    }
    if ($tokens.Count -lt 2) { throw "Cannot resolve authorization groups for $name" }
    $users[$name] = @($tokens | Sort-Object -Unique)
}
$groups = @{}
foreach ($name in @('Stark','Night Watch','Mormont')) {
    # Direct membership is intentional: fail if a nested group is newly introduced.
    $groups[$name] = @(Get-ADGroupMember -Identity $name -Server $cs.Name | ForEach-Object SamAccountName | Sort-Object)
}
@{ users = $users; groups = $groups } | ConvertTo-Json -Depth 6 -Compress
