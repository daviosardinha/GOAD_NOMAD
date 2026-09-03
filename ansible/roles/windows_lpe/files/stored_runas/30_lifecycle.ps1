if ($Action -eq 'apply') {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null

    $SecureRunAs = ConvertTo-SecureString $RunAsPassword -AsPlainText -Force
    $Existing = Get-LocalUser -Name $RunAsUser -ErrorAction SilentlyContinue
    if ($Existing) {
        Set-LocalUser -Name $RunAsUser -Password $SecureRunAs
        Enable-LocalUser -Name $RunAsUser
    }
    else {
        New-LocalUser -Name $RunAsUser -Password $SecureRunAs -PasswordNeverExpires -AccountNeverExpires | Out-Null
    }
    Add-LocalGroupMember -Group 'Administrators' -Member $RunAsUser -ErrorAction SilentlyContinue

    $TargetEscaped = $CredentialTarget.Replace("'", "''")
    $PasswordEscaped = $RunAsPassword.Replace("'", "''")
    $SeedPayload = @(
        "`$CSharp = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$CredentialInteropB64'))"
        'Add-Type -TypeDefinition $CSharp -Language CSharp'
        'try {'
        "    [KingdomInteractiveCredential]::WriteInteractive('$TargetEscaped', '$TargetEscaped', '$PasswordEscaped')"
        '}'
        'catch {'
        '    $ErrorChain = @()'
        '    $CurrentError = $_.Exception'
        '    while ($null -ne $CurrentError) {'
        '        $NativeCode = if ($CurrentError.PSObject.Properties.Name -contains ''NativeErrorCode'') { [string]$CurrentError.NativeErrorCode } else { ''n/a'' }'
        '        $HResultSigned = [int64]$CurrentError.HResult'
        '        $HResultHex = [Convert]::ToString(($HResultSigned -band 4294967295L), 16).PadLeft(8, ''0'')'
        '        $ErrorChain += (''type={0} hresult={1} hex=0x{2} native={3} message={4}'' -f $CurrentError.GetType().FullName, $HResultSigned, $HResultHex, $NativeCode, $CurrentError.Message)'
        '        $CurrentError = $CurrentError.InnerException'
        '    }'
        '    throw (''CredWrite diagnostic: '' + ($ErrorChain -join '' -> ''))'
        '}'
        "& `$env:SystemRoot\System32\cmdkey.exe /list | Set-Content -LiteralPath '__OUTPUT_PATH__' -Encoding utf8"
        'if ($LASTEXITCODE -ne 0) { throw "cmdkey list failed exit=$LASTEXITCODE" }'
    ) -join [Environment]::NewLine

    $SeedListing = Invoke-OwnerPayload 'Seed' $SeedPayload
    if ($SeedListing -notmatch 'Domain:interactive=') {
        throw "seeded credential is not Interactive Logon: $SeedListing"
    }
    if ($SeedListing -notmatch [regex]::Escape($CredentialTarget)) {
        throw 'seeded interactive credential target missing immediately after CredWrite'
    }

    @{
        owner = $Owner
        target = $CredentialTarget
        user = $RunAsUser
        type = 'Interactive Logon'
        flags = 8196
        blob = 'ANSI'
    } | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8

    Write-Output 'WINDOWS_LPE_STORED_RUNAS_CREDENTIALS=APPLIED'
    Assert-VulnerableState
    Write-Output 'WINDOWS_LPE_STORED_RUNAS_CREDENTIALS=VULNERABLE'
}
elseif ($Action -eq 'reset') {
    $TargetEscaped = $CredentialTarget.Replace("'", "''")
    $DeletePayload = @(
        "`$CSharp = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$CredentialInteropB64'))"
        'Add-Type -TypeDefinition $CSharp -Language CSharp'
        "`$Target = '$TargetEscaped'"
        '[KingdomInteractiveCredential]::DeleteInteractive($Target)'
        '& $env:SystemRoot\System32\cmdkey.exe ("/delete:Domain:interactive=" + $Target) 2>&1 | Out-Null'
    ) -join [Environment]::NewLine

    Invoke-OwnerPayload 'Reset' $DeletePayload | Out-Null
    Remove-LocalUser -Name $RunAsUser -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force
    }

    Write-Output 'WINDOWS_LPE_STORED_RUNAS_CREDENTIALS=RESET'
    Assert-CleanState
    Write-Output 'WINDOWS_LPE_STORED_RUNAS_CREDENTIALS=CLEAN'
}
elseif ($Action -eq 'validate' -and $ValidateState -eq 'vulnerable') {
    Assert-VulnerableState
    Write-Output 'WINDOWS_LPE_STORED_RUNAS_CREDENTIALS=VULNERABLE'
}
elseif ($Action -eq 'validate' -and $ValidateState -eq 'clean') {
    Assert-CleanState
    Write-Output 'WINDOWS_LPE_STORED_RUNAS_CREDENTIALS=CLEAN'
}
else {
    throw "unsupported stored RunAs lifecycle action=$Action validateState=$ValidateState"
}
