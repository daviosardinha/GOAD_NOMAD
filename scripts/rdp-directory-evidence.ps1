# Read-only directory evidence, executed on WINTERFELL using existing management.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

function ConvertTo-KingdomsSidValue {
    param([AllowNull()][object]$Sid)
    # AD cmdlets can materialize tokenGroups as SecurityIdentifier objects.
    # Only binary values belong in the byte-array/offset constructor.
    if ($Sid -is [System.Security.Principal.SecurityIdentifier]) {
        return $Sid.Value
    }
    if ($Sid -is [byte[]]) {
        return [System.Security.Principal.SecurityIdentifier]::new($Sid, 0).Value
    }
    if ($Sid -is [string]) {
        return [System.Security.Principal.SecurityIdentifier]::new($Sid).Value
    }
    $typeName = if ($null -eq $Sid) { '<null>' } else { $Sid.GetType().FullName }
    throw "Unsupported directory SID representation: $typeName"
}

# Every directory query below is explicitly pinned to WINTERFELL. Avoid
# initializing the implicit AD: drive during cold-start convergence: ADWS can
# already be listening while default-drive discovery is still transient.
$Env:ADPS_LoadDefaultDrive = '0'
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
    $userSid = ConvertTo-KingdomsSidValue $user.SID
    if ($userSid -ne (ConvertTo-KingdomsSidValue $resolved.SID)) { throw "Directory identity changed for $name" }
    if (-not $user.Enabled) { throw "Disabled account cannot validate RDP policy: $name" }
    $tokens = @($userSid)
    foreach ($groupSid in $user.tokenGroups) {
        try {
            $tokens += ConvertTo-KingdomsSidValue $groupSid
        } catch {
            throw "Cannot normalize tokenGroups for ${name}: $($_.Exception.Message)"
        }
    }
    $tokens = @($tokens | Sort-Object -Unique)
    if ($tokens.Count -lt 2) { throw "Cannot resolve authorization groups for $name" }
    $users[$name] = $tokens
}
$groups = @{}
foreach ($name in @('Stark','Night Watch','Mormont')) {
    # Direct membership is intentional: fail if a nested group is newly introduced.
    $groups[$name] = @(Get-ADGroupMember -Identity $name -Server $cs.Name | ForEach-Object SamAccountName | Sort-Object)
}
@{ users = $users; groups = $groups } | ConvertTo-Json -Depth 6 -Compress
