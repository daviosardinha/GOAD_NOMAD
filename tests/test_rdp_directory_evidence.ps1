# Offline behavioral regression: no AD module, network calls, or Windows changes.
$ErrorActionPreference = 'Stop'
$collector = Join-Path $PSScriptRoot '../scripts/rdp-directory-evidence.ps1'
$mockState = @{ scenario = 'success'; resolvedCount = 0; baseCount = 0; groupCount = 0; expectedDN = '' }

function Import-Module { param($Name) }
function Get-CimInstance {
    param($ClassName)
    [pscustomobject]@{ Name = 'WINTERFELL'; Domain = 'north.sevenkingdoms.local' }
}
function Get-ADUser {
    param($Identity, $Server, $Properties, $LDAPFilter, $SearchBase, $SearchScope)
    if ($Server -ne 'WINTERFELL') { throw 'Query must use the evidence DC' }
    if ($Identity) {
        if ($Properties -contains 'tokenGroups') {
            throw 'tokenGroups cannot be requested during username resolution'
        }
        $mockState.resolvedCount++
        $mockState.expectedDN = "CN=$Identity,DC=north,DC=sevenkingdoms,DC=local"
        return [pscustomobject]@{
            DistinguishedName = $mockState.expectedDN
            SID = [pscustomobject]@{ Value = 'S-1-5-21-1-2-3-1100' }
        }
    }
    if ($SearchScope -ne 'Base' -or $SearchBase -ne $mockState.expectedDN -or
        $LDAPFilter -ne '(objectClass=user)' -or $Properties -notcontains 'tokenGroups') {
        throw 'tokenGroups requires an explicit base query on the resolved DN'
    }
    $mockState.baseCount++
    if ($mockState.scenario -eq 'missing') { return }
    $sid = if ($mockState.scenario -eq 'identity_changed') { 'S-1-5-21-1-2-3-9999' } else { 'S-1-5-21-1-2-3-1100' }
    $groups = if ($mockState.scenario -eq 'no_groups') { @() } else { @('mock-group-bytes') }
    $user = [pscustomobject]@{
        SID = [pscustomobject]@{ Value = $sid }
        Enabled = ($mockState.scenario -ne 'disabled')
        tokenGroups = $groups
    }
    $user
    if ($mockState.scenario -eq 'duplicate') { $user }
}
function New-Object {
    param($TypeName, $ArgumentList)
    if ($TypeName -ne 'System.Security.Principal.SecurityIdentifier') { throw 'Unexpected constructor' }
    # Mock only the Windows SID constructor; this test exercises query sequencing.
    [pscustomobject]@{ Value = 'S-1-5-21-1-2-3-513' }
}
function Get-ADGroupMember {
    param($Identity, $Server)
    if ($Server -ne 'WINTERFELL') { throw 'Group query must use the evidence DC' }
    $mockState.groupCount++
    [pscustomobject]@{ SamAccountName = 'hodor' }
}

$result = (& $collector) | ConvertFrom-Json
if ($mockState.resolvedCount -ne 6 -or $mockState.baseCount -ne 6 -or $mockState.groupCount -ne 3) {
    throw 'Expected six paired account queries and three group queries'
}
foreach ($name in @('hodor','brandon.stark','jon.snow','samwell.tarly','rickon.stark','robb.stark')) {
    $tokens = @($result.users.$name)
    if ($tokens.Count -ne 2 -or $tokens -notcontains 'S-1-5-21-1-2-3-1100' -or
        $tokens -notcontains 'S-1-5-21-1-2-3-513') { throw "Missing tokens for $name" }
}
$failureCases = @{
    missing = 'Expected one directory object'
    duplicate = 'Expected one directory object'
    identity_changed = 'Directory identity changed'
    disabled = 'Disabled account cannot validate RDP policy'
    no_groups = 'Cannot resolve authorization groups'
}
foreach ($case in $failureCases.Keys) {
    $mockState.scenario = $case
    $failure = $null
    try { $null = & $collector } catch { $failure = $_.Exception.Message }
    if (-not $failure -or -not $failure.StartsWith($failureCases[$case])) {
        throw "Expected fail-closed behavior for ${case}; got: $failure"
    }
}
Write-Output 'PASS: base-scope directory collection and five fail-closed cases'
