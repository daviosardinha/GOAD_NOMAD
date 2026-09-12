[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false
Add-Type -Path "$env:windir\System32\inetsrv\Microsoft.Web.Administration.dll"
$manager = New-Object Microsoft.Web.Administration.ServerManager
try {
    $site = $manager.Sites['Default Web Site']
    if ($null -eq $site) { throw 'The existing Default Web Site is required.' }
    $physical = [Environment]::ExpandEnvironmentVariables($site.Applications['/'].VirtualDirectories['/'].PhysicalPath)
    if ($physical.TrimEnd('\') -ine 'C:\inetpub\wwwroot') {
        throw 'Unexpected site root; refusing to configure a different website.'
    }
    $config = $manager.GetApplicationHostConfiguration()
    $prefix = 'system.webServer/security/authentication/'
    $rootAnon = $config.GetSection($prefix + 'anonymousAuthentication', 'Default Web Site')
    if (-not [bool]$rootAnon['enabled']) {
        throw 'Public root anonymous authentication is disabled; investigate baseline drift.'
    }
    $location = 'Default Web Site/internal'
    $anonymous = $config.GetSection($prefix + 'anonymousAuthentication', $location)
    $windows = $config.GetSection($prefix + 'windowsAuthentication', $location)
    if ([bool]$anonymous['enabled']) {
        $anonymous['enabled'] = $false
        $Ansible.Changed = $true
    }
    if (-not [bool]$windows['enabled']) {
        $windows['enabled'] = $true
        $Ansible.Changed = $true
    }
    $providers = $windows.GetCollection('providers')
    $names = @($providers | ForEach-Object { [string]$_['value'] })
    if (($names -join ',') -cne 'Negotiate,NTLM') {
        $providers.Clear()
        foreach ($name in @('Negotiate', 'NTLM')) {
            $entry = $providers.CreateElement('add')
            $entry['value'] = $name
            $providers.Add($entry)
        }
        $Ansible.Changed = $true
    }
    # Writes location settings in ApplicationHost.config without unlocking
    # authentication globally or replacing the site's existing Web.config.
    if ($Ansible.Changed -and -not $Ansible.CheckMode) { $manager.CommitChanges() }
} finally {
    $manager.Dispose()
}
