# VMware helper used by GOAD Vagrant boxes to configure the lab-facing NIC.
# Legacy usage remains supported:
#   fix_ip.ps1 <ip>
#
# GOAD_NOMAD segmented usage:
#   fix_ip.ps1 <ip> <lab_gateway> <lab_mac>
#
# The segmented form identifies the exercise NIC by deterministic MAC address,
# gives it a static /24 address, and installs a persistent route for all
# GOAD_NOMAD internal networks through the Debian router. Vagrant's NAT NIC
# remains the default route during provisioning and is removed/hardened later
# when the lab enters exercise mode.

param (
    [Parameter(Mandatory = $true)]
    [String] $ip,

    [String] $gateway = "",
    [String] $mac = ""
)

$ErrorActionPreference = "Stop"

function Normalize-Mac([String] $value) {
    return ($value -replace '[:-]', '').ToUpperInvariant()
}

$interfaceName = "Ethernet1"
$interfaceIndex = $null

if (-not [String]::IsNullOrWhiteSpace($mac)) {
    $wantedMac = Normalize-Mac $mac
    $adapter = Get-NetAdapter | Where-Object {
        (Normalize-Mac $_.MacAddress) -eq $wantedMac
    } | Select-Object -First 1

    if ($null -eq $adapter) {
        Write-Host "[!] Could not find VMware lab adapter with MAC $mac"
        Get-NetAdapter | Format-Table -AutoSize Name, InterfaceDescription, MacAddress, Status
        throw "GOAD_NOMAD lab adapter not found"
    }

    $interfaceName = $adapter.Name
    $interfaceIndex = $adapter.ifIndex
}

Write-Host "[*] Configuring lab interface '$interfaceName' with $ip/24"
netsh.exe interface ipv4 set address name="$interfaceName" source=static address=$ip mask=255.255.255.0 gateway=none | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure $interfaceName with $ip"
}

if (-not [String]::IsNullOrWhiteSpace($gateway)) {
    # Keep Vagrant NAT as the provisioning default route, but force every
    # GOAD_NOMAD internal subnet (10.4.0.0/16) through the exercise router.
    route.exe DELETE 10.4.0.0 MASK 255.255.0.0 2>$null | Out-Null

    if ($null -ne $interfaceIndex) {
        route.exe -p ADD 10.4.0.0 MASK 255.255.0.0 $gateway METRIC 5 IF $interfaceIndex | Out-Host
    }
    else {
        route.exe -p ADD 10.4.0.0 MASK 255.255.0.0 $gateway METRIC 5 | Out-Host
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to add persistent GOAD_NOMAD route through $gateway"
    }

    Write-Host "[+] Internal route: 10.4.0.0/16 -> $gateway"
}

Write-Host "[+] VMware lab interface configuration complete"
ipconfig.exe | Out-Host
route.exe PRINT 10.4.0.0 | Out-Host
