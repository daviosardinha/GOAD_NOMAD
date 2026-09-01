import os
import re
import socket
import subprocess
import time

import winrm

from goad.goadpath import GoadPath
from goad.log import Log
from goad.provider.vagrant.vagrant import VagrantProvider
from goad.utils import *


class VmwareProvider(VagrantProvider):
    provider_name = VMWARE
    default_provisioner = PROVISIONING_LOCAL
    allowed_provisioners = [PROVISIONING_LOCAL, PROVISIONING_RUNNER, PROVISIONING_DOCKER, PROVISIONING_VM]

    # GOAD_NOMAD Windows guests. Keep this explicit so Linux guests such as the
    # Debian router are never forced through the WinRM / VMware Tools path.
    goad_nomad_windows = [
        'GOAD-DC01',
        'GOAD-DC02',
        'GOAD-DC03',
        'GOAD-SRV02',
        'GOAD-SRV03',
    ]

    def check(self):
        checks = [
            super().check(),
            self.command.check_vmware(),
            self.command.check_vmware_utility(),
            self.command.check_vagrant_plugin('vagrant-vmware-desktop', True)
        ]
        return all(checks)

    def _vmx_path(self, machine):
        machine_id = os.path.join(
            str(self.path), '.vagrant', 'machines', machine, 'vmware_desktop', 'id'
        )
        if not os.path.isfile(machine_id):
            return None
        with open(machine_id, 'r', encoding='utf-8') as handle:
            vmx = handle.read().strip()
        return vmx if vmx else None

    def _winrm_forwarded_port(self, machine):
        result = subprocess.run(
            [self.command.vagrant_bin, 'port', machine],
            cwd=self.path,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        match = re.search(r'5985\s+\(guest\)\s+=>\s+(\d+)\s+\(host\)', result.stdout)
        return int(match.group(1)) if match else None

    @staticmethod
    def _wait_tcp(port, timeout=180):
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=2):
                    return True
            except OSError:
                time.sleep(3)
        return False

    @staticmethod
    def _winrm_session(port):
        return winrm.Session(
            f'http://127.0.0.1:{port}/wsman',
            auth=('vagrant', 'vagrant'),
            transport='ntlm',
            operation_timeout_sec=60,
            read_timeout_sec=90,
        )

    def _wait_winrm_ready(self, port, timeout=180):
        """Wait for a stable WinRM command channel, not merely an open TCP port."""
        deadline = time.time() + timeout
        last_error = None
        while time.time() < deadline:
            try:
                session = self._winrm_session(port)
                result = session.run_ps("Write-Output 'GOAD_WINRM_READY'")
                if result.status_code == 0 and b'GOAD_WINRM_READY' in result.std_out:
                    return True
            except Exception as exc:
                last_error = exc
            time.sleep(5)

        if last_error is not None:
            Log.warning(f'GOAD_NOMAD: WinRM never became stable on port {port}: {last_error}')
        return False

    def _guest_tools_healthy(self, port):
        try:
            session = self._winrm_session(port)
            result = session.run_ps(r'''
$svc = Get-Service -Name VMTools -ErrorAction SilentlyContinue
$file = Test-Path "C:\Program Files\VMware\VMware Tools\vmtoolsd.exe"
if ($svc -and $file) {
    if ($svc.Status -ne 'Running') {
        try {
            Set-Service -Name VMTools -StartupType Automatic -ErrorAction Stop
            Start-Service -Name VMTools -ErrorAction Stop
            $svc = Get-Service -Name VMTools
        } catch {}
    }
    if ($svc.Status -eq 'Running') { Write-Output 'GOAD_VMTOOLS_OK' }
}
''')
            return result.status_code == 0 and b'GOAD_VMTOOLS_OK' in result.std_out
        except Exception:
            return False

    def _wait_guest_ip(self, vmx, timeout=180):
        deadline = time.time() + timeout
        while time.time() < deadline:
            result = subprocess.run(
                ['vmrun', '-T', 'ws', 'getGuestIPAddress', vmx],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
            ip = result.stdout.strip()
            if result.returncode == 0 and ip and not ip.lower().startswith('error'):
                Log.success(f'GOAD_NOMAD: VMware guest IP reporting healthy ({ip})')
                return True
            time.sleep(5)
        return False

    def _install_vmware_tools(self, machine, vmx, port):
        Log.warning(f'GOAD_NOMAD: {machine} has no healthy VMware Tools; bootstrapping them')

        # Workstation can mount the Tools ISO successfully but leave
        # `vmrun installTools` waiting indefinitely. Bound the host command and
        # continue to the in-guest setup discovery: the mounted media is the
        # actual prerequisite, not a clean vmrun exit status.
        try:
            mount = subprocess.run(
                ['vmrun', '-T', 'ws', 'installTools', vmx],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                timeout=30,
            )
            if mount.returncode != 0:
                Log.warning(
                    f'GOAD_NOMAD: vmrun installTools returned {mount.returncode} for {machine}; '
                    'checking for mounted Tools media through WinRM'
                )
        except subprocess.TimeoutExpired:
            Log.warning(
                f'GOAD_NOMAD: vmrun installTools timed out for {machine}; '
                'continuing because Workstation may already have mounted the Tools ISO'
            )

        if not self._wait_tcp(port, 120):
            Log.error(f'GOAD_NOMAD: WinRM port {port} did not become reachable for {machine}')
            return False

        # A listening WinRM socket is not enough. Older Windows boxes can reset
        # the first authenticated request while services are still converging.
        if not self._wait_winrm_ready(port, 180):
            Log.error(f'GOAD_NOMAD: WinRM did not become stable for {machine}')
            return False

        try:
            session = self._winrm_session(port)
            install = session.run_ps(r'''
$ErrorActionPreference = 'Stop'
$deadline = (Get-Date).AddSeconds(90)
$setup = $null
while ((Get-Date) -lt $deadline -and -not $setup) {
    $setup = Get-CimInstance Win32_LogicalDisk |
        Where-Object { $_.DriveType -eq 5 } |
        ForEach-Object {
            $candidate = "$($_.DeviceID)\setup.exe"
            if (Test-Path $candidate) { $candidate }
        } |
        Select-Object -First 1
    if (-not $setup) { Start-Sleep -Seconds 2 }
}
if (-not $setup) { throw 'VMware Tools setup.exe was not found on a mounted CD/DVD drive' }

$p = Start-Process -FilePath $setup -ArgumentList '/S','/v"/qn REBOOT=ReallySuppress"' -Wait -PassThru
Write-Output "GOAD_VMTOOLS_INSTALL_EXIT=$($p.ExitCode)"
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { exit $p.ExitCode }
''')
            if install.status_code != 0:
                Log.error(f'GOAD_NOMAD: VMware Tools installer failed for {machine}')
                return False

            Log.info(f'GOAD_NOMAD: VMware Tools installed on {machine}; rebooting guest')
            session.run_ps("shutdown.exe /r /t 5 /f | Out-Null")
        except Exception as exc:
            # VMware Tools installation/reboot can transiently tear down the
            # WinRM transport itself. Do not immediately call that a failed
            # installation: wait for WinRM/Tools/IP health and accept the
            # recovery if the guest proves healthy afterward.
            Log.warning(
                f'GOAD_NOMAD: VMware Tools WinRM session interrupted for {machine}: {exc}; '
                'checking whether the guest recovered successfully'
            )
            deadline = time.time() + 240
            while time.time() < deadline:
                if self._wait_tcp(port, 15) and self._guest_tools_healthy(port):
                    if self._wait_guest_ip(vmx, 60):
                        Log.success(
                            f'GOAD_NOMAD: VMware Tools recovery completed for {machine} '
                            'despite transient WinRM reset'
                        )
                        return True
                time.sleep(10)

            Log.error(f'GOAD_NOMAD: VMware Tools recovery did not become healthy for {machine}')
            return False

        # The forwarded socket may stay open briefly while Windows restarts.
        time.sleep(15)
        if not self._wait_tcp(port, 240):
            Log.error(f'GOAD_NOMAD: {machine} WinRM did not return after VMware Tools reboot')
            return False

        if not self._wait_winrm_ready(port, 180):
            Log.error(f'GOAD_NOMAD: {machine} WinRM did not stabilize after VMware Tools reboot')
            return False

        deadline = time.time() + 180
        while time.time() < deadline:
            if self._guest_tools_healthy(port):
                break
            time.sleep(5)
        else:
            Log.error(f'GOAD_NOMAD: VMware Tools did not become healthy inside {machine}')
            return False

        if not self._wait_guest_ip(vmx, 180):
            Log.error(f'GOAD_NOMAD: VMware Tools are running but guest IP reporting failed for {machine}')
            return False

        Log.success(f'GOAD_NOMAD: VMware Tools bootstrap complete for {machine}')
        return True

    def _ensure_vmware_tools(self, machine):
        vmx = self._vmx_path(machine)
        if not vmx:
            Log.error(f'GOAD_NOMAD: cannot locate VMX path for {machine}')
            return False

        port = self._winrm_forwarded_port(machine)
        if not port:
            Log.error(f'GOAD_NOMAD: cannot determine forwarded WinRM port for {machine}')
            return False

        if not self._wait_tcp(port, 120):
            Log.error(f'GOAD_NOMAD: forwarded WinRM port {port} is not reachable for {machine}')
            return False

        if self._guest_tools_healthy(port):
            if not self._wait_guest_ip(vmx, 60):
                Log.warning(f'GOAD_NOMAD: {machine} VMware Tools are healthy but guest IP reporting is delayed')
            return True

        return self._install_vmware_tools(machine, vmx, port)

    def install(self):
        """Bring up VMware guests and prepare GOAD_NOMAD local provisioning reachability."""
        if self.lab_name != 'GOAD':
            return super().install()

        # Bring up the router independently so a Windows guest failure cannot
        # prevent creation of the routing plane. Linux keeps the normal SSH path.
        Log.info('GOAD_NOMAD: bringing up segmented router')
        if not self.command.run_vagrant(['up', 'GOAD-ROUTER'], self.path):
            Log.error('GOAD_NOMAD: failed to bring up GOAD-ROUTER')
            return False

        # Windows VMware boxes can expose working forwarded WinRM while VMware
        # Tools are absent. In that state vagrant-vmware-desktop cannot discover
        # the guest IP and aborts with the well-known guest-communication error.
        # Handle each Windows guest independently, repair Tools when necessary,
        # and retry the Vagrant bring-up instead of aborting the complete lab.
        for machine in self.goad_nomad_windows:
            Log.info(f'GOAD_NOMAD: bringing up {machine}')
            first_up = self.command.run_vagrant(['up', machine], self.path)

            if not self._ensure_vmware_tools(machine):
                return False

            if not first_up:
                Log.warning(f'GOAD_NOMAD: retrying {machine} after VMware Tools recovery')
                if not self.command.run_vagrant(['up', machine], self.path):
                    Log.error(f'GOAD_NOMAD: {machine} still failed after VMware Tools recovery')
                    return False

        # The host has no vmnet20/vmnet30 adapters, so local Ansible must
        # temporarily reach those protected networks through GOAD-ROUTER after
        # Vagrant has brought the complete instance up.
        route_script = GoadPath.get_script_file('provisioning-routes.sh')
        if not os.path.isfile(route_script):
            Log.error(f'GOAD_NOMAD provisioning route helper not found: {route_script}')
            return False

        Log.info('GOAD_NOMAD: enabling temporary host routes for local Ansible provisioning')
        # Repository script files are not guaranteed to carry an executable bit
        # after clone/archive operations. Invoke the helper through bash instead
        # of executing it directly so the install path is mode-independent.
        route_result = subprocess.run(['sudo', 'bash', route_script, 'enable'], check=False)
        if route_result.returncode != 0:
            Log.error('GOAD_NOMAD: failed to enable temporary provisioning routes')
            return False

        Log.warning('GOAD_NOMAD: provisioning routes are temporary and must be removed before exercise mode')
        return True
