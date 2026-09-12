[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false
Import-Module ActiveDirectory
$server = 'localhost'
$root = Get-ADRootDSE -Server $server
if ($root.defaultNamingContext -ine 'DC=north,DC=sevenkingdoms,DC=local' -or
    $root.rootDomainNamingContext -ine 'DC=sevenkingdoms,DC=local') {
    throw 'Unexpected domain or forest; refusing the Phase 01 forest setting.'
}
$dn = 'CN=Directory Service,CN=Windows NT,CN=Services,' + $root.configurationNamingContext
$object = Get-ADObject -Identity $dn -Server $server -Properties dSHeuristics
$before = [string]$object.dSHeuristics
# Preserve ALL existing characters, including validation markers at 10, 20, ...
# Pad only a missing/short value; change precisely the seventh character.
$chars = $before.PadRight(7, '0').ToCharArray()
$chars[6] = '2'
$after = -join $chars
$Ansible.Result = @{ before = $before; after = $after }
if ($before -cne $after) {
    $Ansible.Changed = $true
    if (-not $Ansible.CheckMode) {
        Set-ADObject -Identity $dn -Server $server -Replace @{ dSHeuristics = $after }
        $actual = [string](Get-ADObject -Identity $dn -Server $server -Properties dSHeuristics).dSHeuristics
        if ($actual -cne $after) { throw 'dSHeuristics read-back did not match.' }
    }
}
# No ACL additions and no LDAP signing/channel-binding policy changes here.
