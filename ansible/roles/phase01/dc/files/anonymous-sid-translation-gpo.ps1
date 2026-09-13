[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false

Import-Module ActiveDirectory
Import-Module GroupPolicy

$domain = 'north.sevenkingdoms.local'
$domainDn = 'DC=north,DC=sevenkingdoms,DC=local'
$dcFqdn = 'winterfell.north.sevenkingdoms.local'
$targetOu = 'OU=Domain Controllers,DC=north,DC=sevenkingdoms,DC=local'
$gpoName = 'Kingdoms - Phase 01 - Anonymous SID Translation'
$securityExtension = '[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]'

$system = Get-CimInstance Win32_ComputerSystem
if ($system.Name -ine 'WINTERFELL' -or
    $system.Domain -ine $domain -or
    $system.DomainRole -lt 4) {
    throw 'Phase 01 SID-translation GPO provisioning requires WINTERFELL in NORTH.'
}

$adDomain = Get-ADDomain -Identity $domain -Server $dcFqdn
if ($adDomain.DistinguishedName -ine $domainDn) {
    throw "Unexpected NORTH domain DN: $($adDomain.DistinguishedName)"
}

$gpo = Get-GPO -Name $gpoName -Domain $domain -Server $dcFqdn -ErrorAction SilentlyContinue
if ($null -eq $gpo) {
    $Ansible.Changed = $true
    if ($Ansible.CheckMode) {
        $Ansible.Result = @{
            gpo = $gpoName
            target = $targetOu
            action = 'would create dedicated Phase 01 security GPO'
        }
        return
    }
    $gpo = New-GPO -Name $gpoName -Domain $domain -Server $dcFqdn -Comment 'Kingdoms Phase 01 intentionally vulnerable anonymous SID/name translation policy.'
}

$guidText = $gpo.Id.ToString('B').ToUpperInvariant()
$gpoDn = "CN=$guidText,CN=Policies,CN=System,$domainDn"
$gpoRoot = Join-Path $env:SystemRoot "SYSVOL\sysvol\$domain\Policies\$guidText"
$secEditDir = Join-Path $gpoRoot 'Machine\Microsoft\Windows NT\SecEdit'
$templatePath = Join-Path $secEditDir 'GptTmpl.inf'
$gptIniPath = Join-Path $gpoRoot 'GPT.INI'

$desiredTemplate = @'
[Unicode]
Unicode=yes
[System Access]
LSAAnonymousNameLookup = 1
[Version]
signature="$CHICAGO$"
Revision=1
'@

$templateChanged = $false
if (Test-Path $templatePath) {
    $currentTemplate = (Get-Content -LiteralPath $templatePath -Raw).Replace("`r`n", "`n").TrimEnd()
    $wantedTemplate = $desiredTemplate.Replace("`r`n", "`n").TrimEnd()
    $templateChanged = $currentTemplate -cne $wantedTemplate
} else {
    $templateChanged = $true
}

$gpoAd = Get-ADObject -Identity $gpoDn -Server $dcFqdn -Properties gPCMachineExtensionNames,versionNumber
$currentExtensions = [string]$gpoAd.gPCMachineExtensionNames
$extensionChanged = $currentExtensions -notlike '*{827D319E-6EAC-11D2-A4EA-00C04F79F83A}*'

$inheritance = Get-GPInheritance -Target $targetOu -Domain $domain -Server $dcFqdn
$link = @($inheritance.GpoLinks | Where-Object { $_.GpoId -eq $gpo.Id }) | Select-Object -First 1
$linkChanged = $null -eq $link -or -not [bool]$link.Enabled -or [int]$link.Order -ne 1 -or [bool]$link.Enforced

if ($templateChanged -or $extensionChanged -or $linkChanged) {
    $Ansible.Changed = $true
}

if (-not $Ansible.CheckMode) {
    if ($templateChanged) {
        New-Item -ItemType Directory -Path $secEditDir -Force | Out-Null
        [System.IO.File]::WriteAllText($templatePath, ($desiredTemplate.TrimEnd() + "`r`n"), [System.Text.Encoding]::Unicode)
    }

    if ($extensionChanged) {
        $newExtensions = $currentExtensions + $securityExtension
        Set-ADObject -Identity $gpoDn -Server $dcFqdn -Replace @{ gPCMachineExtensionNames = $newExtensions }
    }

    if ($templateChanged -or $extensionChanged) {
        $gpoAd = Get-ADObject -Identity $gpoDn -Server $dcFqdn -Properties versionNumber
        $oldVersion = [uint32]$gpoAd.versionNumber
        $userVersion = ($oldVersion -shr 16) -band 0xFFFF
        $computerVersion = $oldVersion -band 0xFFFF
        if ($computerVersion -ge 0xFFFF) {
            throw 'GPO computer version is exhausted; refusing to wrap the version counter.'
        }
        $newVersion = [uint32](($userVersion -shl 16) -bor ($computerVersion + 1))

        $gptIni = if (Test-Path $gptIniPath) {
            Get-Content -LiteralPath $gptIniPath -Raw
        } else {
            "[General]`r`nVersion=0`r`n"
        }
        if ($gptIni -match '(?im)^Version=\d+\s*$') {
            $gptIni = [regex]::Replace($gptIni, '(?im)^Version=\d+\s*$', "Version=$newVersion")
        } else {
            $gptIni = $gptIni.TrimEnd() + "`r`nVersion=$newVersion`r`n"
        }
        [System.IO.File]::WriteAllText($gptIniPath, $gptIni, [System.Text.Encoding]::ASCII)
        Set-ADObject -Identity $gpoDn -Server $dcFqdn -Replace @{ versionNumber = [int]$newVersion }
    }

    if ($null -eq $link) {
        New-GPLink -Guid $gpo.Id -Target $targetOu -Domain $domain -Server $dcFqdn -LinkEnabled Yes -Enforced No -Order 1 | Out-Null
    } elseif ($linkChanged) {
        Set-GPLink -Guid $gpo.Id -Target $targetOu -Domain $domain -Server $dcFqdn -LinkEnabled Yes -Enforced No -Order 1 | Out-Null
    }
}

$Ansible.Result = @{
    gpo = $gpoName
    id = $gpo.Id.ToString()
    target = $targetOu
    link_order = 1
    setting = 'LSAAnonymousNameLookup=1'
}
