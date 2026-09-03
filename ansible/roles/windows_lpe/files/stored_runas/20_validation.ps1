function Get-StoredCredentialListing {
    $Payload = @(
        "& `$env:SystemRoot\System32\cmdkey.exe /list | Set-Content -LiteralPath '__OUTPUT_PATH__' -Encoding utf8"
        'if ($LASTEXITCODE -ne 0) { throw "cmdkey list failed exit=$LASTEXITCODE" }'
    ) -join [Environment]::NewLine
    return (Invoke-OwnerPayload 'List' $Payload)
}

function Test-RunAsSavedCredential {
    $TargetEscaped = $CredentialTarget.Replace("'", "''")
    $Payload = @(
        "`$Target = '$TargetEscaped'"
        "`$WorkDir = '__WORKDIR__'"
        "`$ProofFile = Join-Path `$WorkDir 'runas-proof.txt'"
        'Remove-Item -LiteralPath $ProofFile -Force -ErrorAction SilentlyContinue'
        "`$Program = `$env:SystemRoot + '\System32\cmd.exe /d /c echo RUNAS_SAVECRED_OK>' + `$ProofFile"
        '$Psi = New-Object System.Diagnostics.ProcessStartInfo'
        '$Psi.FileName = $env:SystemRoot + ''\System32\runas.exe'''
        '$Psi.Arguments = "/savecred /user:$Target `"$Program`""'
        '$Psi.UseShellExecute = $false'
        '$Psi.CreateNoWindow = $true'
        '$Psi.RedirectStandardOutput = $true'
        '$Psi.RedirectStandardError = $true'
        '$Process = [System.Diagnostics.Process]::Start($Psi)'
        'if (-not $Process.WaitForExit(15000)) {'
        '    try { $Process.Kill() } catch { }'
        "    throw 'runas /savecred timed out waiting for saved credential'"
        '}'
        '$Stdout = $Process.StandardOutput.ReadToEnd()'
        '$Stderr = $Process.StandardError.ReadToEnd()'
        '$ProofDeadline = (Get-Date).AddSeconds(10)'
        'while ((Get-Date) -lt $ProofDeadline -and -not (Test-Path -LiteralPath $ProofFile -PathType Leaf)) { Start-Sleep -Milliseconds 250 }'
        'if (-not (Test-Path -LiteralPath $ProofFile -PathType Leaf)) {'
        '    throw ("runas proof failed exit={0} stdout={1} stderr={2}" -f $Process.ExitCode, $Stdout.Trim(), $Stderr.Trim())'
        '}'
        '$Proof = (Get-Content -LiteralPath $ProofFile -Raw).Trim()'
        'if ($Proof -ne ''RUNAS_SAVECRED_OK'') { throw "runas proof marker invalid: $Proof" }'
        "'RUNAS_SAVECRED_OK' | Set-Content -LiteralPath '__OUTPUT_PATH__' -Encoding ascii"
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

    Test-RunAsSavedCredential
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
