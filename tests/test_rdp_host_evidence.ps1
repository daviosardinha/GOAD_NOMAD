# Offline host-collector integration. Execute the production policy logic;
# replace only native Windows reads and account translation with test fixtures.
[CmdletBinding()]
param([switch]$FromStdin)
$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw (Join-Path $PSScriptRoot '../scripts/rdp-host-evidence.ps1')
$directoryJson = Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures/rdp-directory-evidence.json')
$inputParameters = if ($FromStdin) { [Console]::In.ReadToEnd() | ConvertFrom-Json } else { $null }

Add-Type -TypeDefinition @'
using System;
public static class KingdomsRdpReadOnly {
    public static string[] Allow;
    public static string[] Deny;
    public static string[] Sessions;
    public static string[] ReadRight(string name) {
        if (name == "SeRemoteInteractiveLogonRight") return Allow;
        if (name == "SeDenyRemoteInteractiveLogonRight") return Deny;
        throw new ArgumentException("Unexpected right");
    }
    public static string[] RdpUsers() { return Sessions; }
}
'@

# Patch AST-located I/O statements, not the authorization comparisons or loops.
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Host collector parse failure' }
$edits = @()
foreach ($statement in $ast.EndBlock.Statements) {
    $replacement = $null
    if ($statement -is [System.Management.Automation.Language.AssignmentStatementAst]) {
        switch ($statement.Left.Extent.Text) {
            '$aliases' { $replacement = '$aliases = $fixture.Aliases' }
            '$machine' { $replacement = '' }
            '$expectedSids' {
                $replacement = '$expectedSids = @($expected | ForEach-Object { if (-not $fixture.NamedSids.ContainsKey($_)) { throw "Unexpected account $_" }; $fixture.NamedSids[$_] } | Sort-Object)'
            }
        }
    } elseif ($statement -is [System.Management.Automation.Language.ForEachStatementAst] -and
              $statement.Variable.VariablePath.UserPath -eq 'group') {
        $replacement = ''
    }
    if ($null -ne $replacement) {
        $edits += @{ Start = $statement.Extent.StartOffset; Length = $statement.Extent.EndOffset - $statement.Extent.StartOffset; Text = $replacement }
    }
}
if ($edits.Count -ne 4) { throw 'Native read boundaries changed; update the integration fixture deliberately' }
foreach ($edit in $edits | Sort-Object Start -Descending) {
    $source = $source.Remove($edit.Start, $edit.Length).Insert($edit.Start, $edit.Text)
}
function Invoke-HostCollector {
    param([hashtable]$Parameters)
    # Use win_powershell's actual AddScript/AddParameters invocation pattern.
    $ps = [PowerShell]::Create([System.Management.Automation.RunspaceMode]::CurrentRunspace)
    try {
        [void]$ps.AddScript($source).AddParameters($Parameters)
        $result = $ps.Invoke()
        if ($ps.HadErrors) { throw $ps.Streams.Error[0] }
        $result
    } catch {
        $exception = $_.Exception
        while ($null -ne $exception.InnerException) { $exception = $exception.InnerException }
        throw $exception.Message
    } finally { $ps.Dispose() }
}

function Get-CimInstance { param($ClassName) [pscustomobject]@{ Name = $fixture.Host; Domain = $fixture.Domain } }
function Get-Service { param($Name) [pscustomobject]@{ Status = $fixture.Service } }
function Get-ItemProperty { param($Path) [pscustomobject]@{ fDenyTSConnections = $fixture.ListenerDisabled; UserAuthentication = $fixture.Nla } }
function Get-ScheduledTask { param($TaskName) [pscustomobject]@{ State = $fixture.TaskState; Principal = [pscustomobject]@{ UserId = $fixture.TaskOwner } } }
function Get-ScheduledTaskInfo { param($TaskName) [pscustomobject]@{ LastTaskResult = $fixture.TaskResult } }
function gpresult.exe { $global:LASTEXITCODE = $fixture.GpExit; 'MOCK_GPRESULT' }

function New-HostFixture {
    param([string]$HostName)
    [KingdomsRdpReadOnly]::Allow = @('S-1-5-32-544','S-1-5-32-555')
    [KingdomsRdpReadOnly]::Deny = @()
    [KingdomsRdpReadOnly]::Sessions = @()
    $aliases = @{ 'S-1-5-32-544' = @('S-1-5-21-1-2-3-9999'); 'S-1-5-32-555' = @() }
    switch ($HostName) {
        WINTERFELL { $aliases['S-1-5-32-544'] = @('S-1-5-21-1-2-3-1106') }
        CASTELBLACK { $aliases['S-1-5-32-555'] = @('S-1-5-21-1-2-3-1106') }
        WS01 { $aliases['S-1-5-32-555'] = @('S-1-5-21-1-2-3-1105') }
    }
    @{
        Host = $HostName; Domain = 'north.sevenkingdoms.local'; Aliases = $aliases
        NamedSids = @{ 'NORTH\rickon.stark' = 'S-1-5-21-1-2-3-1105'; 'NORTH\robb.stark' = 'S-1-5-21-1-2-3-1106' }
        Service = 'Running'; ListenerDisabled = 0; Nla = 1; GpExit = 0
        TaskState = 'Ready'; TaskResult = 0; TaskOwner = 'NORTH\robb.stark'
    }
}

foreach ($hostName in @('WINTERFELL','CASTELBLACK','WS01')) {
    $fixture = New-HostFixture $hostName
    $parameters = @{ ExpectedHost = $hostName; DirectoryJson = $directoryJson; RequireSessions = $false }
    if ($FromStdin) {
        $rendered = $inputParameters.$hostName
        if ($rendered.DirectoryJson -isnot [string]) { throw 'Ansible did not preserve DirectoryJson as a string' }
        if ($rendered.ExpectedHost -cne $hostName -or $rendered.RequireSessions -isnot [bool]) { throw 'Invalid rendered parameters' }
        foreach ($key in @('ExpectedHost','DirectoryJson','RequireSessions')) { $parameters[$key] = $rendered.$key }
    }
    $output = @(Invoke-HostCollector $parameters)
    if ($output -notcontains "RDP_POLICY_CONTRACT=${hostName}:PASS") { throw "No complete PASS for $hostName" }
    if (@($output | Where-Object { $_ -like 'RDP_POLICY=*' }).Count -ne 6) { throw 'Must check all six identities' }
    foreach ($name in @('hodor','brandon.stark','jon.snow','samwell.tarly','rickon.stark','robb.stark')) {
        $want = if (($name -eq 'rickon.stark' -and $hostName -eq 'WS01') -or
                    ($name -eq 'robb.stark' -and $hostName -ne 'WS01')) { 'ALLOW' } else { 'DENY' }
        if ($output -notcontains "RDP_POLICY=${hostName}:NORTH\${name}:$want") { throw "Wrong decision for $name on $hostName" }
    }
    if ($output -notcontains 'DESKTOP_LOGON_MATRIX=NOT_EXECUTED:policy evidence is not a fresh logon test') { throw 'Missing evidence limitation' }
}

$failures = @{
    bad_json = 'Invalid directory evidence JSON'
    missing_user = 'Directory evidence must contain exactly'
    invalid_sid = 'Invalid directory SID evidence'
    empty_tokens = 'Incomplete directory SID evidence'
    wrong_host = 'Unexpected machine/domain'
    wrong_domain = 'Unexpected machine/domain'
    broad_allow = 'Unexpected effective SeRemoteInteractiveLogonRight'
    broad_membership = 'RDP membership mismatch'
    missing_alias = 'Cannot resolve built-in RDP'
    direct_admin = 'Recovered user has direct/nested admin membership'
    nested_admin = 'Recovered user has direct/nested admin membership'
    direct_deny = 'Unexpected applicable RDP deny'
    nested_deny = 'Unexpected applicable RDP deny'
    stopped_service = 'RDP service is not running'
    disabled_listener = 'RDP listener disabled'
    disabled_nla = 'RDP NLA must remain enabled'
    missing_session = 'Required existing RDP session not observed'
    failed_gpresult = 'Cannot read resultant computer Group Policy'
    broken_bot = 'connect_bot health check failed'
    wrong_bot_owner = 'connect_bot is not owned by'
}
foreach ($case in $failures.Keys) {
    $hostName = if ($case -in @('broken_bot','wrong_bot_owner')) { 'WINTERFELL' } else { 'WS01' }
    $fixture = New-HostFixture $hostName
    $parameters = @{ ExpectedHost = $hostName; DirectoryJson = $directoryJson; RequireSessions = $false }
    switch ($case) {
        bad_json { $parameters.DirectoryJson = 'System.Collections.Hashtable' }
        missing_user { $data = $directoryJson | ConvertFrom-Json; $data.users.psobject.Properties.Remove('hodor'); $parameters.DirectoryJson = $data | ConvertTo-Json -Depth 8 }
        invalid_sid { $data = $directoryJson | ConvertFrom-Json; $data.users.hodor = @('bad', 'S-1-5-11'); $parameters.DirectoryJson = $data | ConvertTo-Json -Depth 8 }
        empty_tokens { $data = $directoryJson | ConvertFrom-Json; $data.users.hodor = @(); $parameters.DirectoryJson = $data | ConvertTo-Json -Depth 8 }
        wrong_host { $fixture.Host = 'OTHER' }
        wrong_domain { $fixture.Domain = 'other.local' }
        broad_allow { [KingdomsRdpReadOnly]::Allow += 'S-1-5-11' }
        broad_membership { $fixture.Aliases['S-1-5-32-555'] += 'S-1-5-21-1-2-3-2001' }
        missing_alias { $fixture.Aliases.Remove('S-1-5-32-555') }
        direct_admin { $fixture.Aliases['S-1-5-32-544'] += 'S-1-5-21-1-2-3-1105' }
        nested_admin { $fixture.Aliases['S-1-5-32-544'] += 'S-1-5-21-9-9-9-1000'; $fixture.Aliases['S-1-5-21-9-9-9-1000'] = @('S-1-5-21-1-2-3-2001') }
        direct_deny { [KingdomsRdpReadOnly]::Deny = @('S-1-5-21-1-2-3-1105') }
        nested_deny { [KingdomsRdpReadOnly]::Deny = @('S-1-5-21-9-9-9-1000'); $fixture.Aliases['S-1-5-21-9-9-9-1000'] = @('S-1-5-21-1-2-3-2001') }
        stopped_service { $fixture.Service = 'Stopped' }
        disabled_listener { $fixture.ListenerDisabled = 1 }
        disabled_nla { $fixture.Nla = 0 }
        missing_session { $parameters.RequireSessions = $true }
        failed_gpresult { $fixture.GpExit = 1 }
        broken_bot { $fixture.TaskResult = 1 }
        wrong_bot_owner { $fixture.TaskOwner = 'NORTH\other' }
    }
    $failure = $null
    try { $null = Invoke-HostCollector $parameters } catch { $failure = $_.Exception.Message }
    if (-not $failure -or -not $failure.StartsWith($failures[$case])) { throw "Expected rejection for ${case}; got: $failure" }
}
foreach ($hostName in @('CASTELBLACK','WS01')) {
    $fixture = New-HostFixture $hostName
    [KingdomsRdpReadOnly]::Sessions = if ($hostName -eq 'WS01') { @('NORTH\rickon.stark') } else { @('NORTH\robb.stark') }
    $output = @(Invoke-HostCollector @{ ExpectedHost = $hostName; DirectoryJson = $directoryJson; RequireSessions = $true })
    if ($output -notcontains "RDP_POLICY_CONTRACT=${hostName}:PASS") { throw 'Expected observed-session acceptance' }
}
Write-Output 'PASS: three-host policy matrix, twenty negative cases, and required-session checks (Windows reads mocked)'
