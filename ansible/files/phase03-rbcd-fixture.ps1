# Kingdoms Phase 03: one-attribute RBCD lesson on CASTELBLACK.
# Executed by ansible.windows.win_powershell on WINTERFELL only.
# Changes no GPO, domain-wide ACL, RDP group, service, or forest trust.
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('audit', 'apply', 'reset')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false
Import-Module ActiveDirectory -ErrorAction Stop

$dc = 'winterfell.north.sevenkingdoms.local'
$domainName = 'north.sevenkingdoms.local'
$targetDn = 'CN=CASTELBLACK,CN=Computers,DC=north,DC=sevenkingdoms,DC=local'
$grantee = 'rickon.stark'
$exerciseComputerSam = 'K03RBCD$'
$exerciseComputerDn = 'CN=K03RBCD,CN=Computers,DC=north,DC=sevenkingdoms,DC=local'
$attributeGuid = [guid]'3f78c3e5-f79a-46bd-a0b8-9d18116ddc79'
$stateDir = Join-Path $env:ProgramData 'GOAD-Kingdoms\phase03-rbcd'
$statePath = Join-Path $stateDir 'castelblack-preimage.json'

$hostIdentity = Get-CimInstance Win32_ComputerSystem
if ($hostIdentity.Name -ine 'WINTERFELL' -or
    $hostIdentity.Domain -ine $domainName -or
    $hostIdentity.DomainRole -lt 4) {
    throw 'Not WINTERFELL in NORTH; refusing to inspect or mutate the fixture.'
}

$domain = Get-ADDomain -Identity $domainName -Server $dc
if ($domain.DNSRoot -ine $domainName) {
    throw 'NORTH domain identity mismatch.'
}
$target = Get-ADComputer -Identity 'CASTELBLACK' -Server $dc -Properties 'msDS-AllowedToActOnBehalfOfOtherIdentity', ObjectGUID
$rickon = Get-ADUser -Identity $grantee -Server $dc -Properties SID
if ($target.DistinguishedName -ine $targetDn) {
    throw "CASTELBLACK moved or has unexpected DN: $($target.DistinguishedName)."
}
$training = @(Get-ADComputer -LDAPFilter '(sAMAccountName=K03RBCD$)' -SearchBase $domain.DistinguishedName -Server $dc -Properties 'mS-DS-CreatorSID', MemberOf)
if ($training.Count -gt 1) {
    throw 'Unexpected duplicate exercise computer accounts.'
}
$rbcd = $target.'msDS-AllowedToActOnBehalfOfOtherIdentity'
$adPath = 'AD:\' + $target.DistinguishedName
$acl = Get-Acl -Path $adPath
$rights = [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty
$access = [System.Security.AccessControl.AccessControlType]::Allow
$inherit = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::None
$rule = [System.DirectoryServices.ActiveDirectoryAccessRule]::new($rickon.SID, $rights, $access, $attributeGuid, $inherit)
$aclSection = [System.Security.AccessControl.AccessControlSections]::Access

function Get-FixtureRules($descriptor) {
    @($descriptor.Access | Where-Object {
        $sid = $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        $sid -eq $rickon.SID.Value -and
        $_.ActiveDirectoryRights -eq $rights -and
        $_.AccessControlType -eq $access -and
        $_.ObjectType -eq $attributeGuid -and
        $_.InheritanceType -eq $inherit -and
        -not $_.IsInherited
    })
}

function Save-FixtureState($state) {
    $json = ConvertTo-Json -InputObject $state -Depth 4
    $temp = $statePath + '.tmp'
    [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $statePath -Force
}

function Read-FixtureState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return $null
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.Version -ne 1 -or
        $state.TargetGuid -ne $target.ObjectGUID.ToString() -or
        $state.RickonSid -ne $rickon.SID.Value -or
        $state.TargetDn -ine $targetDn -or
        $state.TrainingComputer -ne $exerciseComputerSam -or
        -not $state.InitialDacl -or
        -not $state.InitialOwner) {
        throw 'Fixture preimage does not match this domain, object or grantee; refusing.'
    }
    return $state
}

# The AD PowerShell module may materialize this NT-Sec-Desc attribute as
# ActiveDirectorySecurity rather than the byte[] returned by LDAP libraries.
# Normalize it without trusting or rewriting the descriptor.
function Convert-RbcdToBytes($value) {
    if ($null -eq $value) {
        return $null
    }
    if ($value -is [byte[]]) {
        return ,([byte[]]$value)
    }
    if ($value -is [System.DirectoryServices.ActiveDirectorySecurity]) {
        return ,([byte[]]$value.GetSecurityDescriptorBinaryForm())
    }
    throw ("Unsupported RBCD attribute CLR type: {0}; refusing reset." -f $value.GetType().FullName)
}

function Get-RbcdTrusteeSids($value) {
    $rawBytes = Convert-RbcdToBytes $value
    if ($null -eq $rawBytes -or $rawBytes.Length -eq 0) {
        throw 'RBCD attribute exists but has no parseable security descriptor.'
    }
    $descriptor = [System.Security.AccessControl.RawSecurityDescriptor]::new([byte[]]$rawBytes, 0)
    if ($null -eq $descriptor.DiscretionaryAcl) {
        throw 'RBCD descriptor does not contain a DACL.'
    }
    return @($descriptor.DiscretionaryAcl | ForEach-Object {
        # Only an explicit allow ACE for our exact trustee can be cleaned up.
        if ($_.AceType -ne [System.Security.AccessControl.AceType]::AccessAllowed -or
            $_.AceFlags -ne [System.Security.AccessControl.AceFlags]::None) {
            throw 'RBCD contains an unexpected ACE type or ACE flags.'
        }
        $_.SecurityIdentifier.Value
    })
}

function Assert-ExpectedTrainingComputer {
    if ($training.Count -eq 0) {
        return
    }
    $item = $training[0]
    if ($item.DistinguishedName -ine $exerciseComputerDn -or
        $item.SamAccountName -ine $exerciseComputerSam -or
        @($item.MemberOf | Where-Object { $null -ne $_ }).Count -ne 0) {
        throw 'Exercise computer was renamed, moved or given group membership. Review manually.'
    }
    $createdBy = $item.'mS-DS-CreatorSID'
    if ($null -eq $createdBy) {
        throw 'Exercise computer has no creator SID; it cannot be safely removed automatically.'
    }
    if ($createdBy -is [byte[]]) {
        $creatorSid = [System.Security.Principal.SecurityIdentifier]::new([byte[]]$createdBy, 0).Value
    } else {
        $creatorSid = $createdBy.ToString()
    }
    if ($creatorSid -ne $rickon.SID.Value) {
        throw 'Exercise computer was not created by Rickon; refusing automatic removal.'
    }
}

$matching = @(Get-FixtureRules $acl)
$dacl = $acl.GetSecurityDescriptorSddlForm($aclSection)
$state = Read-FixtureState
if ($null -ne $state -and $acl.Owner -ine $state.InitialOwner) {
    throw 'CASTELBLACK object owner changed since the fixture preimage; review before continuing.'
}

if ($Mode -eq 'audit') {
    $rbcdTrustees = @()
    $rbcdParseStatus = 'Absent'
    if ($null -ne $rbcd) {
        try {
            $rbcdTrustees = @(Get-RbcdTrusteeSids $rbcd)
            $rbcdParseStatus = 'Parsed'
        } catch {
            $rbcdParseStatus = 'Rejected: ' + $_.Exception.Message
        }
    }
    $Ansible.Result = @{
        Mode = 'audit'
        Host = $hostIdentity.Name
        Target = $target.DistinguishedName
        Owner = $acl.Owner
        RickonSid = $rickon.SID.Value
        FixtureAceCount = $matching.Count
        RbcdPresent = ($null -ne $rbcd)
        RbcdValueType = $(if ($null -ne $rbcd) { $rbcd.GetType().FullName } else { 'Absent' })
        RbcdParseStatus = $rbcdParseStatus
        RbcdTrusteeSids = $rbcdTrustees
        TrainingAccountCount = $training.Count
        TrainingAccountPresent = ($training.Count -ne 0)
        ManagedFixture = ($null -ne $state)
        DaclMatchesApplied = ($null -ne $state -and $dacl -ceq $state.AppliedDacl)
    }
    return
}

if ($matching.Count -gt 1) {
    throw 'Duplicate exact RBCD fixture ACEs; refusing to change the target ACL.'
}

if ($Mode -eq 'apply') {
    if ($null -eq $state) {
        if ($matching.Count -ne 0 -or $null -ne $rbcd -or $training.Count -ne 0) {
            throw 'Expected an untouched CASTELBLACK RBCD baseline and an unused K03RBCD account.'
        }
        $quota = (Get-ADObject -Identity $domain.DistinguishedName -Server $dc -Properties 'ms-DS-MachineAccountQuota').'ms-DS-MachineAccountQuota'
        if ([int]$quota -lt 1) {
            throw 'NORTH machine-account quota is zero; lesson prerequisite missing.'
        }
        $state = [ordered]@{
            Version = 1
            TargetDn = $targetDn
            TargetGuid = $target.ObjectGUID.ToString()
            RickonSid = $rickon.SID.Value
            TrainingComputer = $exerciseComputerSam
            InitialDacl = $dacl
            InitialOwner = $acl.Owner
            AppliedDacl = ''
            CreatedUtc = [datetime]::UtcNow.ToString('o')
        }
    } elseif ($matching.Count -eq 1) {
        if ($dacl -cne $state.AppliedDacl) {
            throw 'Existing fixture DACL has drifted; refusing to overwrite other changes.'
        }
        $Ansible.Result = @{ Mode = 'apply'; State = 'already-applied'; Target = 'CASTELBLACK'; Changed = $false }
        return
    } elseif ($dacl -cne $state.InitialDacl -or $null -ne $rbcd -or $training.Count -ne 0) {
        throw 'Incomplete fixture has diverged from its preimage; refusing automatic recovery.'
    }

    if ($Ansible.CheckMode) {
        $Ansible.Changed = $true
        $Ansible.Result = @{ Mode = 'apply'; State = 'would-add-exact-attribute-ace'; Target = 'CASTELBLACK'; Attribute = 'msDS-AllowedToActOnBehalfOfOtherIdentity'; Grantee = 'NORTH\rickon.stark'; WouldChange = $true }
        return
    }

    $acl.AddAccessRule($rule)
    $state.AppliedDacl = $acl.GetSecurityDescriptorSddlForm($aclSection)
    if (-not (Test-Path -LiteralPath $stateDir -PathType Container)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        & icacls.exe $stateDir '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Cannot protect the Phase 03 preimage directory.'
        }
    }
    Save-FixtureState $state
    Set-Acl -Path $adPath -AclObject $acl -ErrorAction Stop
    $actual = (Get-Acl -Path $adPath).GetSecurityDescriptorSddlForm($aclSection)
    if (@(Get-FixtureRules (Get-Acl -Path $adPath)).Count -ne 1) {
        throw 'Post-apply verification failed: the exact RBCD ACE was not installed.'
    }
    $state.AppliedDacl = $actual
    Save-FixtureState $state
    $Ansible.Changed = $true
    $Ansible.Result = @{ Mode = 'apply'; State = 'exact-attribute-ace-installed'; Target = 'CASTELBLACK' }
    return
}

# Reset is intentionally guarded: no preimage, unrelated DACL edits, unknown RBCD
# trustees, or a foreign exercise computer will ever be removed automatically.
if ($null -eq $state) {
    if ($matching.Count -ne 0 -or $null -ne $rbcd -or $training.Count -ne 0) {
        throw 'No fixture preimage exists, but the target is not in the expected baseline.'
    }
    $Ansible.Result = @{ Mode = 'reset'; State = 'already-reset'; Target = 'CASTELBLACK' }
    return
}
if (($matching.Count -eq 1 -and $dacl -cne $state.AppliedDacl) -or
    ($matching.Count -eq 0 -and $dacl -cne $state.InitialDacl)) {
    throw 'The CASTELBLACK DACL changed outside this fixture. Manual review required.'
}

Assert-ExpectedTrainingComputer

if ($null -ne $rbcd) {
    if ($training.Count -ne 1) {
        throw ("Expected one owned exercise computer; observed {0}. Refusing reset." -f $training.Count)
    }
    $rbcdSids = @(Get-RbcdTrusteeSids $rbcd)
    if ($rbcdSids.Count -ne 1 -or
        $rbcdSids[0] -ne $training[0].SID.Value) {
        throw 'RBCD contains unexpected trustees. Preserve it for manual review.'
    }
}
if ($Ansible.CheckMode) {
    $Ansible.Changed = $true
    $Ansible.Result = @{ Mode = 'reset'; State = 'would-restore-original-attribute-and-dacl'; Target = 'CASTELBLACK'; WouldChange = $true }
    return
}

if ($null -ne $rbcd) {
    Set-ADComputer -Identity $target.DistinguishedName -Server $dc -Clear 'msDS-AllowedToActOnBehalfOfOtherIdentity'
    $Ansible.Changed = $true
}

if ($matching.Count -eq 1) {
    $acl.RemoveAccessRuleSpecific($rule)
    if ($acl.GetSecurityDescriptorSddlForm($aclSection) -cne $state.InitialDacl) {
        throw 'Removing the fixture ACE did not recreate the original DACL; refusing Set-Acl.'
    }
    Set-Acl -Path $adPath -AclObject $acl -ErrorAction Stop
    if ((Get-Acl -Path $adPath).GetSecurityDescriptorSddlForm($aclSection) -cne $state.InitialDacl) {
        throw 'The original DACL was not restored; preserve the preimage for review.'
    }
    $Ansible.Changed = $true
}

if ($training.Count -eq 1) {
    Remove-ADComputer -Identity $training[0].DistinguishedName -Server $dc -Confirm:$false
    $Ansible.Changed = $true
}
Remove-Item -LiteralPath $statePath -Force
$Ansible.Result = @{ Mode = 'reset'; State = 'baseline-restored'; Target = 'CASTELBLACK' }
