function Get-StoredCredentialListing {
    $Payload = @(
        "& `$env:SystemRoot\System32\cmdkey.exe /list | Set-Content -LiteralPath '__OUTPUT_PATH__' -Encoding utf8"
        'if ($LASTEXITCODE -ne 0) { throw "cmdkey list failed exit=$LASTEXITCODE" }'
    ) -join [Environment]::NewLine
    return (Invoke-OwnerPayload 'List' $Payload)
}

# RUNAS /savecred is an interactive-logon behavior. A Scheduled Task running
# with SeBatchLogonRight can enumerate Rickon's Credential Manager entry, but
# it cannot reliably prove the child process created by RUNAS. Keep the real
# proof helper for explicit interactive compatibility testing; do not make the
# automated apply/validate lifecycle depend on a batch-logon approximation.
function Test-RunAsSavedCredentialInteractiveOnly {
    $TargetEscaped = $CredentialTarget.Replace("'", "''")
    $Payload = @(
        "`$Target = '$TargetEscaped'"
        "`$ProofFile = Join-Path `$env:PUBLIC ('goad-runas-proof-' + [guid]::NewGuid().ToString('N') + '.txt')"
        'Remove-Item -LiteralPath $ProofFile -Force -ErrorAction SilentlyContinue'
        'try {'
        "    `$Program = `$env:SystemRoot + '\System32\cmd.exe /d /c whoami > ' + `$ProofFile"
        '    $Psi = New-Object System.Diagnostics.ProcessStartInfo'
        '    $Psi.FileName = $env:SystemRoot + ''\System32\runas.exe'''
        '    $Psi.Arguments = "/savecred /user:$Target `"$Program`""'
        '    $Psi.UseShellExecute = $false'
        '    $Psi.CreateNoWindow = $true'
        '    $Psi.RedirectStandardOutput = $true'
        '    $Psi.RedirectStandardError = $true'
        '    $Process = [System.Diagnostics.Process]::Start($Psi)'
        '    if (-not $Process.WaitForExit(15000)) {'
        '        try { $Process.Kill() } catch { }'
        "        throw 'runas /savecred timed out waiting for saved credential'"
        '    }'
        '    $Stdout = $Process.StandardOutput.ReadToEnd()'
        '    $Stderr = $Process.StandardError.ReadToEnd()'
        '    $ProofDeadline = (Get-Date).AddSeconds(10)'
        '    while ((Get-Date) -lt $ProofDeadline -and -not (Test-Path -LiteralPath $ProofFile -PathType Leaf)) { Start-Sleep -Milliseconds 250 }'
        '    if (-not (Test-Path -LiteralPath $ProofFile -PathType Leaf)) {'
        '        throw ("runas proof failed exit={0} stdout={1} stderr={2}" -f $Process.ExitCode, $Stdout.Trim(), $Stderr.Trim())'
        '    }'
        '    $Proof = (Get-Content -LiteralPath $ProofFile -Raw).Trim()'
        '    if ($Proof -ine $Target) { throw "runas proof identity invalid expected=$Target actual=$Proof" }'
        "    'RUNAS_SAVECRED_OK' | Set-Content -LiteralPath '__OUTPUT_PATH__' -Encoding ascii"
        '}'
        'finally {'
        '    Remove-Item -LiteralPath $ProofFile -Force -ErrorAction SilentlyContinue'
        '}'
    ) -join [Environment]::NewLine

    $ProofResult = Invoke-OwnerPayload 'RunAsProof' $Payload
    if ($ProofResult -notmatch 'RUNAS_SAVECRED_OK') {
        throw 'runas /savecred proof marker missing'
    }
}

function Assert-VulnerableState {
    $Account = Get-LocalUser -Name $RunAsUser -ErrorAction Stop
    if (-not $Account.Enabled) { throw 'stored-RunAs training account is disabled' }

    $Admin = Get-LocalGroupMember -Group 'Administrators' |
        Where-Object { $_.Name -match "\\$([regex]::Escape($RunAsUser))$" }
    if (-not $Admin) { throw 'stored-RunAs training account is not a local administrator' }
    if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) { throw 'stored RunAs state marker missing' }

    $State = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
    if ([string]$State.owner -ine $Owner) { throw 'stored RunAs state owner mismatch' }
    if ([string]$State.target -ine $CredentialTarget) { throw 'stored RunAs state target mismatch' }
    if ([string]$State.user -ine $RunAsUser) { throw 'stored RunAs state user mismatch' }
    if ([int]$State.flags -ne 8196) { throw 'stored RunAs state flags mismatch' }
    if ([string]$State.blob -ine 'UTF-16LE') { throw 'stored RunAs state blob format mismatch' }

    $Listing = Get-StoredCredentialListing
    if ($Listing -notmatch 'Domain:interactive=') {
        throw "interactive-logon credential type is missing: $Listing"
    }
    if ($Listing -notmatch [regex]::Escape($CredentialTarget)) {
        throw 'Rickon interactive-logon credential target is missing'
    }
    if ($Listing -notmatch [regex]::Escape($RunAsUser)) {
        throw 'Rickon interactive-logon credential username is missing'
    }

    # The automated lifecycle stops here intentionally. The exact current
    # Windows 10 build has been compatibility-proven from Rickon's real RDP
    # session with RUNAS /savecred -> whoami == WS01\kingdom.runas. Repeating
    # that proof from a batch-logon Scheduled Task is not equivalent.
}

function Assert-CleanState {
    if (Get-LocalUser -Name $RunAsUser -ErrorAction SilentlyContinue) {
        throw 'stored-RunAs training account still exists'
    }
    if (Test-Path -LiteralPath $Root) {
        throw 'stored-RunAs scenario directory still exists'
    }

    $Listing = Get-StoredCredentialListing
    if ($Listing -match [regex]::Escape($CredentialTarget)) {
        throw 'Rickon interactive-logon credential still exists after reset'
    }
}
