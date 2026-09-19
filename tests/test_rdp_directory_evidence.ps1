# Offline behavioral regression: no AD module, network calls, or Windows changes.
$ErrorActionPreference = 'Stop'
$collectorText = Get-Content -Raw (Join-Path $PSScriptRoot '../scripts/rdp-directory-evidence.ps1')
$mockState = @{ scenario = 'success'; representation = 'typed'; resolvedCount = 0; baseCount = 0; groupCount = 0; expectedDN = '' }
$binary1 = [byte[]]@(1,2,0,0,0,0,0,5,32,0,0,0,33,2,0,0)
$binary2 = [byte[]]@(1,1,0,0,0,0,0,5,11,0,0,0)
$groupSid1 = 'S-1-5-32-545'
$groupSid2 = 'S-1-5-11'

if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    # Windows PowerShell 5.1 / PowerShell 7: exercise the REAL SID constructors.
    $fixtureSidType = [System.Security.Principal.SecurityIdentifier]
    Write-Output 'SID_TEST_BACKEND=WINDOWS_NATIVE'
} else {
    # .NET SID APIs are Windows-only. This narrow Linux stand-in checks overload
    # binding and representation dispatch, NOT native Windows SID behavior.
    Add-Type -TypeDefinition @'
using System;
public sealed class KingdomsSidFixture {
    public string Value { get; private set; }
    public KingdomsSidFixture(string value) {
        if (value == null || !System.Text.RegularExpressions.Regex.IsMatch(value, @"^S-1-\d+(-\d+)+$"))
            throw new ArgumentException("Invalid SID fixture");
        Value = value;
    }
    public KingdomsSidFixture(byte[] bytes, int offset) {
        if (bytes == null || offset != 0) throw new ArgumentException("Invalid binary SID fixture");
        string key = BitConverter.ToString(bytes);
        if (key == "01-02-00-00-00-00-00-05-20-00-00-00-21-02-00-00") Value = "S-1-5-32-545";
        else if (key == "01-01-00-00-00-00-00-05-0B-00-00-00") Value = "S-1-5-11";
        else throw new ArgumentException("Invalid binary SID fixture");
    }
}
'@
    $fixtureSidType = [KingdomsSidFixture]
    $collectorText = $collectorText.Replace('[System.Security.Principal.SecurityIdentifier]', '[KingdomsSidFixture]')
    Write-Output 'SID_TEST_BACKEND=LINUX_TYPED_STAND_IN; WINDOWS_NATIVE=NOT_RUN'
}
$collector = [scriptblock]::Create($collectorText)

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
            SID = $fixtureSidType::new('S-1-5-21-1-2-3-1100')
        }
    }
    if ($SearchScope -ne 'Base' -or $SearchBase -ne $mockState.expectedDN -or
        $LDAPFilter -ne '(objectClass=user)' -or $Properties -notcontains 'tokenGroups') {
        throw 'tokenGroups requires an explicit base query on the resolved DN'
    }
    $mockState.baseCount++
    if ($mockState.scenario -eq 'missing') { return }
    $sid = if ($mockState.scenario -eq 'identity_changed') { 'S-1-5-21-1-2-3-9999' } else { 'S-1-5-21-1-2-3-1100' }
    switch ($mockState.representation) {
        'typed' { $groups = @($fixtureSidType::new($groupSid1), $fixtureSidType::new($groupSid2)) }
        'binary' { $groups = @($binary1, $binary2) }
        'string' { $groups = @($groupSid1, $groupSid2) }
        'mixed' { $groups = @($fixtureSidType::new($groupSid1), $binary2, $groupSid1) }
    }
    switch ($mockState.scenario) {
        'no_groups' { $groups = @() }
        'only_self' { $groups = @($fixtureSidType::new($sid), $fixtureSidType::new($sid)) }
        'unsupported' { $groups = @([pscustomobject]@{ Value = $groupSid1 }) }
        'null_group' { $groups = @($null) }
        'bad_string' { $groups = @('not-a-sid') }
        'bad_bytes' { $groups = @(,[byte[]]@(0,1)) }
    }
    $user = [pscustomobject]@{
        SID = $fixtureSidType::new($sid)
        Enabled = ($mockState.scenario -ne 'disabled')
        tokenGroups = $groups
    }
    $user
    if ($mockState.scenario -eq 'duplicate') { $user }
}
function Get-ADGroupMember {
    param($Identity, $Server)
    if ($Server -ne 'WINTERFELL') { throw 'Group query must use the evidence DC' }
    $mockState.groupCount++
    [pscustomobject]@{ SamAccountName = 'hodor' }
}

foreach ($representation in @('typed', 'binary', 'string', 'mixed')) {
    $mockState.representation = $representation
    $mockState.resolvedCount = 0
    $mockState.baseCount = 0
    $mockState.groupCount = 0
    $result = (& $collector) | ConvertFrom-Json
    if ($mockState.resolvedCount -ne 6 -or $mockState.baseCount -ne 6 -or $mockState.groupCount -ne 3) {
        throw 'Expected six paired account queries and three group queries'
    }
    foreach ($name in @('hodor','brandon.stark','jon.snow','samwell.tarly','rickon.stark','robb.stark')) {
        $tokens = @($result.users.$name)
        if ($tokens.Count -ne 3 -or $tokens -notcontains 'S-1-5-21-1-2-3-1100' -or
            $tokens -notcontains $groupSid1 -or $tokens -notcontains $groupSid2) {
            throw "Missing/duplicate tokens for $name ($representation)"
        }
    }
}
$failureCases = @{
    missing = 'Expected one directory object'
    duplicate = 'Expected one directory object'
    identity_changed = 'Directory identity changed'
    disabled = 'Disabled account cannot validate RDP policy'
    no_groups = 'Cannot resolve authorization groups'
    only_self = 'Cannot resolve authorization groups'
    unsupported = 'Cannot normalize tokenGroups for hodor: Unsupported directory SID representation'
    null_group = 'Cannot normalize tokenGroups for hodor: Unsupported directory SID representation'
    bad_string = 'Cannot normalize tokenGroups for hodor:'
    bad_bytes = 'Cannot normalize tokenGroups for hodor:'
}
foreach ($case in $failureCases.Keys) {
    $mockState.scenario = $case
    $failure = $null
    try { $null = & $collector } catch { $failure = $_.Exception.Message }
    if (-not $failure -or -not $failure.StartsWith($failureCases[$case])) {
        throw "Expected fail-closed behavior for ${case}; got: $failure"
    }
}
Write-Output 'PASS: base-scope queries, four SID representations, deduplication, and ten fail-closed cases'
