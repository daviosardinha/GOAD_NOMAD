[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Action,

    [Parameter(Mandatory = $true)]
    [string] $ValidateState,

    [Parameter(Mandatory = $true)]
    [PSCredential] $OwnerCredential,

    [Parameter(Mandatory = $true)]
    [PSCredential] $RunAsCredential,

    [Parameter(Mandatory = $true)]
    [string] $CredentialTarget,

    [Parameter(Mandatory = $true)]
    [string] $Root
)

$ErrorActionPreference = 'Stop'
$Owner = $OwnerCredential.UserName
$OwnerPassword = $OwnerCredential.GetNetworkCredential().Password
$RunAsUser = $RunAsCredential.UserName
$RunAsPassword = $RunAsCredential.GetNetworkCredential().Password
$StateFile = Join-Path $Root 'state.json'
$PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$ExchangeRoot = Join-Path $env:ProgramData 'GOAD-Kingdoms'
$RuntimeTarget = "$env:COMPUTERNAME\$RunAsUser"

if ($CredentialTarget -ine $RuntimeTarget) {
    throw "stored RunAs target mismatch configured=$CredentialTarget runtime=$RuntimeTarget"
}

# RUNAS /savecred's Interactive Logon credential format is undocumented.
# Keep the interop as fixed Base64 data and prove compatibility with a real
# RUNAS /savecred execution before calling the scenario vulnerable.
$CredentialInteropB64 = 'dXNpbmcgU3lzdGVtOwp1c2luZyBTeXN0ZW0uQ29tcG9uZW50TW9kZWw7CnVzaW5nIFN5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNlczsKdXNpbmcgU3lzdGVtLlRleHQ7CgpwdWJsaWMgc3RhdGljIGNsYXNzIEtpbmdkb21JbnRlcmFjdGl2ZUNyZWRlbnRpYWwKewogICAgW1N0cnVjdExheW91dChMYXlvdXRLaW5kLlNlcXVlbnRpYWwsIENoYXJTZXQgPSBDaGFyU2V0LlVuaWNvZGUpXQogICAgcHVibGljIHN0cnVjdCBDUkVERU5USUFMCiAgICB7CiAgICAgICAgcHVibGljIHVpbnQgRmxhZ3M7CiAgICAgICAgcHVibGljIHVpbnQgVHlwZTsKICAgICAgICBbTWFyc2hhbEFzKFVubWFuYWdlZFR5cGUuTFBXU3RyKV0gcHVibGljIHN0cmluZyBUYXJnZXROYW1lOwogICAgICAgIFtNYXJzaGFsQXMoVW5tYW5hZ2VkVHlwZS5MUFdTdHIpXSBwdWJsaWMgc3RyaW5nIENvbW1lbnQ7CiAgICAgICAgcHVibGljIFN5c3RlbS5SdW50aW1lLkludGVyb3BTZXJ2aWNlcy5Db21UeXBlcy5GSUxFVElNRSBMYXN0V3JpdHRlbjsKICAgICAgICBwdWJsaWMgdWludCBDcmVkZW50aWFsQmxvYlNpemU7CiAgICAgICAgcHVibGljIEludFB0ciBDcmVkZW50aWFsQmxvYjsKICAgICAgICBwdWJsaWMgdWludCBQZXJzaXN0OwogICAgICAgIHB1YmxpYyB1aW50IEF0dHJpYnV0ZUNvdW50OwogICAgICAgIHB1YmxpYyBJbnRQdHIgQXR0cmlidXRlczsKICAgICAgICBbTWFyc2hhbEFzKFVubWFuYWdlZFR5cGUuTFBXU3RyKV0gcHVibGljIHN0cmluZyBUYXJnZXRBbGlhczsKICAgICAgICBbTWFyc2hhbEFzKFVubWFuYWdlZFR5cGUuTFBXU3RyKV0gcHVibGljIHN0cmluZyBVc2VyTmFtZTsKICAgIH0KCiAgICBbRGxsSW1wb3J0KCJhZHZhcGkzMi5kbGwiLCBFbnRyeVBvaW50ID0gIkNyZWRXcml0ZVciLCBDaGFyU2V0ID0gQ2hhclNldC5Vbmljb2RlLCBTZXRMYXN0RXJyb3IgPSB0cnVlKV0KICAgIHN0YXRpYyBleHRlcm4gYm9vbCBDcmVkV3JpdGVXKHJlZiBDUkVERU5USUFMIGNyZWRlbnRpYWwsIHVpbnQgZmxhZ3MpOwoKICAgIFtEbGxJbXBvcnQoImFkdmFwaTMyLmRsbCIsIEVudHJ5UG9pbnQgPSAiQ3JlZERlbGV0ZVciLCBDaGFyU2V0ID0gQ2hhclNldC5Vbmljb2RlLCBTZXRMYXN0RXJyb3IgPSB0cnVlKV0KICAgIHN0YXRpYyBleHRlcm4gYm9vbCBDcmVkRGVsZXRlVyhzdHJpbmcgdGFyZ2V0TmFtZSwgdWludCB0eXBlLCB1aW50IGZsYWdzKTsKCiAgICBwdWJsaWMgc3RhdGljIHZvaWQgV3JpdGVJbnRlcmFjdGl2ZShzdHJpbmcgdGFyZ2V0LCBzdHJpbmcgdXNlcm5hbWUsIHN0cmluZyBwYXNzd29yZCkKICAgIHsKICAgICAgICBieXRlW10gYmxvYkJ5dGVzID0gRW5jb2RpbmcuVW5pY29kZS5HZXRCeXRlcyhwYXNzd29yZCk7CiAgICAgICAgSW50UHRyIGJsb2IgPSBNYXJzaGFsLkFsbG9jSEdsb2JhbChibG9iQnl0ZXMuTGVuZ3RoKTsKICAgICAgICB0cnkKICAgICAgICB7CiAgICAgICAgICAgIE1hcnNoYWwuQ29weShibG9iQnl0ZXMsIDAsIGJsb2IsIGJsb2JCeXRlcy5MZW5ndGgpOwoKICAgICAgICAgICAgQ1JFREVOVElBTCBjcmVkZW50aWFsID0gbmV3IENSRURFTlRJQUwoKTsKICAgICAgICAgICAgY3JlZGVudGlhbC5GbGFncyA9IDgxOTY7CiAgICAgICAgICAgIGNyZWRlbnRpYWwuVHlwZSA9IDI7CiAgICAgICAgICAgIGNyZWRlbnRpYWwuVGFyZ2V0TmFtZSA9IHRhcmdldDsKICAgICAgICAgICAgY3JlZGVudGlhbC5DcmVkZW50aWFsQmxvYlNpemUgPSAodWludClibG9iQnl0ZXMuTGVuZ3RoOwogICAgICAgICAgICBjcmVkZW50aWFsLkNyZWRlbnRpYWxCbG9iID0gYmxvYjsKICAgICAgICAgICAgY3JlZGVudGlhbC5QZXJzaXN0ID0gMzsKICAgICAgICAgICAgY3JlZGVudGlhbC5Vc2VyTmFtZSA9IHVzZXJuYW1lOwoKICAgICAgICAgICAgaWYgKCFDcmVkV3JpdGVXKHJlZiBjcmVkZW50aWFsLCAwKSkKICAgICAgICAgICAgICAgIHRocm93IG5ldyBXaW4zMkV4Y2VwdGlvbihNYXJzaGFsLkdldExhc3RXaW4zMkVycm9yKCksICJDcmVkV3JpdGVXIGludGVyYWN0aXZlIGNyZWRlbnRpYWwgZmFpbGVkIik7CiAgICAgICAgfQogICAgICAgIGZpbmFsbHkKICAgICAgICB7CiAgICAgICAgICAgIGZvciAoaW50IGkgPSAwOyBpIDwgYmxvYkJ5dGVzLkxlbmd0aDsgaSsrKSBNYXJzaGFsLldyaXRlQnl0ZShibG9iLCBpLCAwKTsKICAgICAgICAgICAgTWFyc2hhbC5GcmVlSEdsb2JhbChibG9iKTsKICAgICAgICB9CiAgICB9CgogICAgcHVibGljIHN0YXRpYyB2b2lkIERlbGV0ZUludGVyYWN0aXZlKHN0cmluZyB0YXJnZXQpCiAgICB7CiAgICAgICAgaWYgKCFDcmVkRGVsZXRlVyh0YXJnZXQsIDIsIDApKQogICAgICAgIHsKICAgICAgICAgICAgaW50IGVycm9yID0gTWFyc2hhbC5HZXRMYXN0V2luMzJFcnJvcigpOwogICAgICAgICAgICBpZiAoZXJyb3IgIT0gMTE2OCAmJiBlcnJvciAhPSA4NykKICAgICAgICAgICAgICAgIHRocm93IG5ldyBXaW4zMkV4Y2VwdGlvbihlcnJvciwgIkNyZWREZWxldGVXIGludGVyYWN0aXZlIGNyZWRlbnRpYWwgZmFpbGVkIik7CiAgICAgICAgfQogICAgfQp9Cg=='

function Remove-TransientTask([string] $TaskName) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Invoke-OwnerPayload([string] $Purpose, [string] $Payload) {
    $Nonce = [guid]::NewGuid().ToString('N')
    $TaskName = "GOAD-Kingdoms-StoredRunAs-$Purpose-$Nonce"
    $WorkDir = Join-Path $ExchangeRoot "StoredRunAs-$Nonce"
    $ScriptPath = Join-Path $WorkDir 'payload.ps1'
    $StatusPath = Join-Path $WorkDir 'status.txt'
    $OutputPath = Join-Path $WorkDir 'output.txt'

    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    $DirAcl = Get-Acl -LiteralPath $WorkDir
    foreach ($Principal in @($Owner, $RuntimeTarget)) {
        if ($Principal -ieq $RuntimeTarget -and -not (Get-LocalUser -Name $RunAsUser -ErrorAction SilentlyContinue)) { continue }
        $DirRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Principal,
            [System.Security.AccessControl.FileSystemRights]::Modify,
            [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $DirAcl.AddAccessRule($DirRule) | Out-Null
    }
    Set-Acl -LiteralPath $WorkDir -AclObject $DirAcl

    $Payload = $Payload.Replace('__OUTPUT_PATH__', $OutputPath.Replace("'", "''"))
    $Payload = $Payload.Replace('__WORKDIR__', $WorkDir.Replace("'", "''"))
    $Wrapped = @(
        '$ErrorActionPreference = ''Stop'''
        'try {'
        $Payload
        "    'OK' | Set-Content -LiteralPath '$StatusPath' -Encoding ascii"
        '} catch {'
        "    (`$_.Exception.Message + [Environment]::NewLine + (`$_ | Out-String)) | Set-Content -LiteralPath '$OutputPath' -Encoding utf8"
        "    'ERROR' | Set-Content -LiteralPath '$StatusPath' -Encoding ascii"
        '    exit 1'
        '}'
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath $ScriptPath -Value $Wrapped -Encoding UTF8

    try {
        Remove-TransientTask $TaskName
        $TaskAction = New-ScheduledTaskAction -Execute $PowerShellExe -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddHours(1)
        Register-ScheduledTask -TaskName $TaskName -Action $TaskAction -Trigger $Trigger -User $Owner -Password $OwnerPassword -RunLevel Limited -Force | Out-Null
        Start-ScheduledTask -TaskName $TaskName

        $Deadline = (Get-Date).AddSeconds(60)
        while ((Get-Date) -lt $Deadline -and -not (Test-Path -LiteralPath $StatusPath -PathType Leaf)) {
            Start-Sleep -Milliseconds 500
        }

        if (-not (Test-Path -LiteralPath $StatusPath -PathType Leaf)) {
            $Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            $Info = if ($Task) { $Task | Get-ScheduledTaskInfo } else { $null }
            $State = if ($Task) { [string]$Task.State } else { 'Missing' }
            $Last = if ($Info) { [uint32]$Info.LastTaskResult } else { [uint32]0 }
            throw ("owner task timed out purpose={0} state={1} last=0x{2:X8}" -f $Purpose, $State, $Last)
        }

        $Status = (Get-Content -LiteralPath $StatusPath -Raw).Trim()
        $Detail = if (Test-Path -LiteralPath $OutputPath -PathType Leaf) { Get-Content -LiteralPath $OutputPath -Raw } else { '' }
        if ($Status -ne 'OK') { throw "owner task failed purpose=$Purpose detail=$Detail" }
        return $Detail
    }
    finally {
        Remove-TransientTask $TaskName
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $ExchangeRoot -PathType Container) {
            if (@(Get-ChildItem -LiteralPath $ExchangeRoot -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                Remove-Item -LiteralPath $ExchangeRoot -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
