$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false

$deadline = (Get-Date).AddSeconds(25)
$active = $null
$explorer = $null

while ((Get-Date) -lt $deadline) {
    $sessions = @(& quser.exe 2>$null)
    $active = @(
        $sessions |
            Where-Object {
                $_ -match '(?i)rickon\.stark' -and
                $_ -match '(?i)\bActive\b'
            }
    ) | Select-Object -First 1

    $explorer = Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue |
        Where-Object { $_.UserName -ieq 'NORTH\rickon.stark' } |
        Select-Object -First 1

    if ($active -and $explorer) {
        break
    }

    Start-Sleep -Seconds 1
}

if (-not $active) {
    throw 'No fresh Active Rickon RDP session is visible'
}
if (-not $explorer) {
    throw 'Rickon Explorer process is not visible in the fresh desktop session'
}

if (-not ('KingdomsFreshTokenProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class KingdomsFreshTokenProbe {
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(
        IntPtr ProcessHandle,
        UInt32 DesiredAccess,
        out IntPtr TokenHandle
    );

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr Handle);
}
'@
}

$token = [IntPtr]::Zero
if (-not [KingdomsFreshTokenProbe]::OpenProcessToken(
    $explorer.Handle,
    0x0008,
    [ref]$token
)) {
    throw "OpenProcessToken failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}

try {
    $identity = [System.Security.Principal.WindowsIdentity]::new($token)
    $groups = @($identity.Groups | ForEach-Object { $_.Value })
    $isAdmin = $groups -contains 'S-1-5-32-544'

    Write-Output "FRESH_RDP_SESSION=$($active.Trim())"
    Write-Output "TOKEN_IDENTITY=$($identity.Name)"
    Write-Output "TOKEN_EXPLORER_PID=$($explorer.Id)"
    Write-Output "TOKEN_ADMIN_SID_PRESENT=$isAdmin"

    if ($identity.Name -ine 'NORTH\rickon.stark') {
        throw "Unexpected token identity: $($identity.Name)"
    }
    if ($isAdmin) {
        throw 'Rickon fresh desktop token contains BUILTIN\Administrators'
    }
}
finally {
    if ($token -ne [IntPtr]::Zero) {
        [void][KingdomsFreshTokenProbe]::CloseHandle($token)
    }
}

Write-Output 'RDP_FRESH_SESSION=PASS'
Write-Output 'RDP_FRESH_TOKEN_NONADMIN=PASS'
