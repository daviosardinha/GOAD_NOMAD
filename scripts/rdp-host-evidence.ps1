# Read-only effective RDP policy and existing session evidence. No logon attempts,
# password handling, policy refresh, group changes, task starts or session resets.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ExpectedHost,
    [Parameter(Mandatory=$true)][string]$DirectoryJson,
    [bool]$RequireSessions = $false
)
$ErrorActionPreference = 'Stop'
function Resolve-KingdomsAccountSid {
    param([AllowEmptyString()][string]$Identity)
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'Account identity is empty' }
    if ($Identity -match '^S-[0-9]+-') {
        return [System.Security.Principal.SecurityIdentifier]::new($Identity).Value
    }
    return [System.Security.Principal.NTAccount]::new($Identity).Translate(
        [System.Security.Principal.SecurityIdentifier]).Value
}

try {
    $directory = $DirectoryJson | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "Invalid directory evidence JSON; check the Ansible parameter handoff: $($_.Exception.Message)"
}
$requiredUsers = @('hodor','brandon.stark','jon.snow','samwell.tarly','rickon.stark','robb.stark')
$evidenceUsers = @($directory.users.psobject.Properties.Name | Sort-Object)
if (($evidenceUsers -join ',') -cne (($requiredUsers | Sort-Object) -join ',')) {
    throw 'Directory evidence must contain exactly the six expected identities'
}
foreach ($name in $requiredUsers) {
    $sidValues = @($directory.users.$name)
    if ($sidValues.Count -lt 2) { throw "Incomplete directory SID evidence for $name" }
    foreach ($value in $sidValues) {
        if ($value -isnot [string] -or $value -cnotmatch '^S-1-[0-9]+(-[0-9]+)+$') {
            throw "Invalid directory SID evidence for $name"
        }
    }
}
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.Name -ine $ExpectedHost -or $cs.Domain -ine 'north.sevenkingdoms.local') {
    throw 'Unexpected machine/domain; refusing to validate the wrong target'
}
$expected = switch ($ExpectedHost.ToUpperInvariant()) {
    'WINTERFELL' { @() }
    'CASTELBLACK' { @('NORTH\robb.stark') }
    'WS01' { @('NORTH\rickon.stark') }
    default { throw 'Host is outside the Kingdoms RDP contract' }
}

# Read LSA directly so effective user rights are checked without writing a
# secedit export to a managed host. SIDs avoid localized built-in group names.
if (-not ('KingdomsRdpReadOnly' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
public static class KingdomsRdpReadOnly {
    [StructLayout(LayoutKind.Sequential)] struct Attributes {
        public int Length; public IntPtr Root; public IntPtr Name;
        public uint Flags; public IntPtr Descriptor; public IntPtr QoS;
    }
    [StructLayout(LayoutKind.Sequential)] struct LsaString {
        public ushort Length; public ushort MaximumLength; public IntPtr Buffer;
    }
    [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr system,
        ref Attributes attributes, uint access, out IntPtr handle);
    [DllImport("advapi32.dll")] static extern uint LsaEnumerateAccountsWithUserRight(
        IntPtr handle, ref LsaString right, out IntPtr buffer, out uint count);
    [DllImport("advapi32.dll")] static extern uint LsaNtStatusToWinError(uint status);
    [DllImport("advapi32.dll")] static extern uint LsaFreeMemory(IntPtr buffer);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr handle);
    public static string[] ReadRight(string name) {
        var a = new Attributes(); a.Length = Marshal.SizeOf(typeof(Attributes));
        IntPtr handle, buffer = IntPtr.Zero;
        uint status = LsaOpenPolicy(IntPtr.Zero, ref a, 0x801, out handle);
        if (status != 0) throw new Win32Exception((int)LsaNtStatusToWinError(status));
        var right = new LsaString(); right.Buffer = Marshal.StringToHGlobalUni(name);
        right.Length = (ushort)(name.Length * 2); right.MaximumLength = (ushort)(right.Length + 2);
        try {
            uint count;
            status = LsaEnumerateAccountsWithUserRight(handle, ref right, out buffer, out count);
            if (status == 0x8000001A) return new string[0]; // STATUS_NO_MORE_ENTRIES
            if (status != 0) throw new Win32Exception((int)LsaNtStatusToWinError(status));
            var result = new List<string>();
            for (int i = 0; i < count; ++i)
                result.Add(new SecurityIdentifier(Marshal.ReadIntPtr(buffer, i * IntPtr.Size)).Value);
            return result.ToArray();
        } finally {
            if (buffer != IntPtr.Zero) LsaFreeMemory(buffer);
            Marshal.FreeHGlobal(right.Buffer); LsaClose(handle);
        }
    }
    [StructLayout(LayoutKind.Sequential)] struct Session {
        public int Id; public IntPtr Station; public int State;
    }
    [DllImport("wtsapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool WTSEnumerateSessionsW(IntPtr server, int reserved, int version,
        out IntPtr sessions, out int count);
    [DllImport("wtsapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool WTSQuerySessionInformationW(IntPtr server, int id, int info,
        out IntPtr buffer, out int bytes);
    [DllImport("wtsapi32.dll")] static extern void WTSFreeMemory(IntPtr buffer);
    static string SessionText(int id, int info) {
        IntPtr p; int n;
        if (!WTSQuerySessionInformationW(IntPtr.Zero, id, info, out p, out n))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        try { return Marshal.PtrToStringUni(p) ?? ""; }
        finally { WTSFreeMemory(p); }
    }
    public static string[] RdpUsers() {
        IntPtr p; int count;
        if (!WTSEnumerateSessionsW(IntPtr.Zero, 0, 1, out p, out count))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            var result = new List<string>(); int size = Marshal.SizeOf(typeof(Session));
            for (int i = 0; i < count; ++i) {
                var s = (Session)Marshal.PtrToStructure(IntPtr.Add(p, i * size), typeof(Session));
                if (s.Id == 0 || (s.State != 0 && s.State != 4)) continue;
                IntPtr protocol; int bytes;
                if (!WTSQuerySessionInformationW(IntPtr.Zero, s.Id, 16, out protocol, out bytes))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                bool rdp;
                try { rdp = bytes >= 2 && Marshal.ReadInt16(protocol) == 2; }
                finally { WTSFreeMemory(protocol); }
                if (rdp) result.Add(SessionText(s.Id, 7) + "\\" + SessionText(s.Id, 5));
            }
            return result.ToArray();
        } finally { WTSFreeMemory(p); }
    }
}
'@
}

$allow = @([KingdomsRdpReadOnly]::ReadRight('SeRemoteInteractiveLogonRight') | Sort-Object)
$deny = @([KingdomsRdpReadOnly]::ReadRight('SeDenyRemoteInteractiveLogonRight') | Sort-Object)
if (($allow -join ',') -ne 'S-1-5-32-544,S-1-5-32-555') {
    throw "Unexpected effective SeRemoteInteractiveLogonRight: $($allow -join ',')"
}

# WinNT works for member-machine SAM and the built-in domain groups on a DC.
# Expand all local aliases to catch indirect admin/deny membership as well.
$aliases = @{}
$machine = [ADSI]("WinNT://" + $env:COMPUTERNAME + ',computer')
foreach ($group in @($machine.psbase.Children | Where-Object { $_.SchemaClassName -eq 'group' })) {
    $groupBytes = $group.InvokeGet('objectSID')
    $sid = [System.Security.Principal.SecurityIdentifier]::new([byte[]]$groupBytes, 0).Value
    $members = @()
    foreach ($rawMember in @($group.psbase.Invoke('Members'))) {
        $member = [ADSI]$rawMember
        $bytes = $member.InvokeGet('objectSID')
        $members += [System.Security.Principal.SecurityIdentifier]::new([byte[]]$bytes, 0).Value
    }
    $aliases[$sid] = $members
}
if (-not $aliases.ContainsKey('S-1-5-32-555') -or -not $aliases.ContainsKey('S-1-5-32-544')) {
    throw 'Cannot resolve built-in RDP and Administrators memberships'
}
$expectedSids = @($expected | ForEach-Object {
    [System.Security.Principal.NTAccount]::new([string]$_).Translate([System.Security.Principal.SecurityIdentifier]).Value
} | Sort-Object)
$actualSids = @($aliases['S-1-5-32-555'] | Sort-Object)
if (($expectedSids -join ',') -ne ($actualSids -join ',')) {
    throw "RDP membership mismatch: expected=$($expectedSids -join ',') actual=$($actualSids -join ',')"
}
Write-Output "RDP_MEMBERSHIP=$($cs.Name):PASS"
Write-Output "ADMINISTRATORS_SIDS=$($aliases['S-1-5-32-544'] -join ',')"
Write-Output "RDP_ALLOW_SIDS=$($allow -join ',')"
Write-Output "RDP_DENY_SIDS=$($deny -join ',')"

foreach ($property in $directory.users.psobject.Properties) {
    $name = $property.Name
    # AD tokenGroups can include the DC's BUILTIN aliases. Resolve those against
    # THIS host, otherwise Robb's DC admin membership looks like WS01 admin.
    $tokens = @($property.Value | Where-Object { $_ -notlike 'S-1-5-32-*' }) +
        @('S-1-1-0','S-1-5-11','S-1-5-4','S-1-5-14','S-1-5-15')
    do {
        $before = $tokens.Count
        foreach ($alias in $aliases.Keys) {
            if ($tokens -notcontains $alias -and @($aliases[$alias] | Where-Object { $tokens -contains $_ }).Count -gt 0) {
                $tokens += $alias
            }
        }
    } while ($tokens.Count -ne $before)
    $applicableDeny = @($deny | Where-Object { $tokens -contains $_ })
    if ($applicableDeny.Count -gt 0) { throw "Unexpected applicable RDP deny for ${name}: $($applicableDeny -join ',')" }
    $isAdmin = $tokens -contains 'S-1-5-32-544'
    if ($name -ne 'robb.stark' -and $isAdmin) { throw "Recovered user has direct/nested admin membership: $name" }
    $permitted = ($isAdmin -or $tokens -contains 'S-1-5-32-555') -and
        @($allow | Where-Object { $tokens -contains $_ }).Count -gt 0
    $wanted = ($name -eq 'rickon.stark' -and $ExpectedHost -ieq 'WS01') -or
        ($name -eq 'robb.stark' -and $ExpectedHost -ine 'WS01')
    if ($permitted -ne $wanted) { throw "RDP policy mismatch for $name on $ExpectedHost" }
    $decision = if ($permitted) { 'ALLOW' } else { 'DENY' }
    Write-Output "RDP_POLICY=$($cs.Name):NORTH\${name}:$decision"
}

if ((Get-Service TermService).Status -ne 'Running') { throw 'RDP service is not running' }
if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server').fDenyTSConnections -ne 0) {
    throw 'RDP listener disabled'
}
if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp').UserAuthentication -ne 1) {
    throw 'RDP NLA must remain enabled'
}
$sessions = @([KingdomsRdpReadOnly]::RdpUsers())
Write-Output "OBSERVED_RDP_SESSIONS=$($sessions -join ',')"
$requiredSession = switch ($ExpectedHost.ToUpperInvariant()) {
    'CASTELBLACK' { 'NORTH\robb.stark' }
    'WS01' { 'NORTH\rickon.stark' }
    default { $null }
}
if ($requiredSession -and $sessions -notcontains $requiredSession) {
    if ($RequireSessions) { throw "Required existing RDP session not observed: $requiredSession" }
    Write-Output "SESSION_EVIDENCE=PENDING:$requiredSession"
}
if ($ExpectedHost -ieq 'WINTERFELL') {
    $task = Get-ScheduledTask -TaskName connect_bot -TaskPath '\'
    $info = Get-ScheduledTaskInfo -TaskName connect_bot -TaskPath '\'
    if ($task.State.ToString() -notin @('Ready','Running') -or $info.LastTaskResult -ne 0) {
        throw 'connect_bot health check failed'
    }
    # Compare account identities, not Task Scheduler's display/storage format.
    $taskIdentity = [string]$task.Principal.UserId
    Write-Output "CONNECT_BOT_PRINCIPAL=$taskIdentity"
    try {
        $expectedBotSid = Resolve-KingdomsAccountSid 'NORTH\robb.stark'
        $actualBotSid = Resolve-KingdomsAccountSid $taskIdentity
    } catch {
        throw "Cannot resolve connect_bot principal '$taskIdentity' or expected NORTH\robb.stark: $($_.Exception.Message)"
    }
    Write-Output "CONNECT_BOT_PRINCIPAL_SID=$actualBotSid"
    Write-Output "CONNECT_BOT_EXPECTED_SID=$expectedBotSid"
    if ($directory.users.'robb.stark' -notcontains $expectedBotSid) {
        throw 'Resolved NORTH\robb.stark SID does not match the directory evidence'
    }
    if ($actualBotSid -ne $expectedBotSid) {
        throw "connect_bot runs as unexpected account '$taskIdentity' (SID $actualBotSid); expected NORTH\robb.stark (SID $expectedBotSid)"
    }
    Write-Output 'CONNECT_BOT_PRINCIPAL_CHECK=PASS'
}
& gpresult.exe /scope computer /r
if ($LASTEXITCODE -ne 0) { throw 'Cannot read resultant computer Group Policy' }
Write-Output "RDP_POLICY_CONTRACT=$($cs.Name):PASS"
Write-Output 'DESKTOP_LOGON_MATRIX=NOT_EXECUTED:policy evidence is not a fresh logon test'
