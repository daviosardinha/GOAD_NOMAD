import ipaddress
import os
import re
import signal
import subprocess
import time

import psutil

from goad.goadpath import GoadPath
from goad.log import Log
from goad.provider.vagrant.vmware_nomad import GoadNomadVmwareProvider


class GoadKingdomsVmwareProvider(GoadNomadVmwareProvider):
    """GOAD Kingdoms VMware provider policy layered over the M1 lifecycle.

    ``GoadNomadVmwareProvider`` remains the compatibility implementation that
    owns the already-validated segmented lifecycle. New GOAD Kingdoms safety
    policy is added here so M2 changes do not casually rewrite the M1 core.
    """

    def _require_cached_sudo(self):
        """Require an already-authenticated sudo timestamp without prompting.

        GOAD Kingdoms lifecycle commands must never stop deep inside a provider
        transition waiting for an unexpected password prompt. Long install/ws01
        lifecycles prime sudo once at the console boundary and refresh it with a
        non-interactive keepalive. Direct provider/mode operations still require
        an existing sudo cache. Every privileged transition re-checks the cache
        non-interactively and fails before changing runtime state if credentials
        are unavailable or expired.
        """
        result = subprocess.run(
            ['sudo', '-n', '-v'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            detail = result.stderr.strip()
            if detail:
                Log.error(f'GOAD Kingdoms: sudo cache unavailable: {detail}')
            Log.error(
                'GOAD Kingdoms: administrative credentials are not cached; '
                'run `sudo -v` in this terminal, then repeat the command'
            )
            return False

        return True

    def _check_segmented_instance_conflicts(self):
        if not self.is_goad_nomad_segmented():
            return True

        if self.path is None:
            Log.error('GOAD Kingdoms: provider path is unavailable for collision preflight')
            return False

        guard = self._script('check-vmware-instance-conflicts.sh')
        if guard is None:
            return False

        Log.info('GOAD Kingdoms: checking for conflicting running segmented VMware instances')
        result = subprocess.run(
            ['bash', guard, os.path.realpath(str(self.path))],
            check=False,
        )
        if result.returncode != 0:
            Log.error(
                'GOAD Kingdoms: VMware bring-up blocked because another running '
                'guest owns one or more deterministic segmented MAC identities'
            )
            return False

        Log.success('GOAD Kingdoms: segmented VMware instance collision preflight passed')
        return True

    @staticmethod
    def _vagrant_cleanup_members(pgid):
        """Snapshot live group members, with fresh executable/PID identities.

        A started vmware-vmx can inherit Vagrant's process group. Group
        membership therefore establishes scope, never permission to signal it.
        Inspection failures propagate so cleanup cannot guess at a target.
        """
        members = {}
        for pid in psutil.pids():
            try:
                if os.getpgid(pid) != pgid:
                    continue
                proc = psutil.Process(pid)
                if proc.status() == psutil.STATUS_ZOMBIE:
                    continue
                name = os.path.basename(proc.exe())
                if not name:
                    raise RuntimeError(f'cannot identify executable for PID {pid}')
                members[pid] = (proc.create_time(), proc.ppid(), name)
            except (psutil.NoSuchProcess, ProcessLookupError):
                continue
        return members

    @staticmethod
    def _vagrant_cleanup_targets(members, leader, preserved):
        """Protect VM monitors and their descendants; allow known controllers."""
        protected = {
            pid for pid, (created, _, name) in members.items()
            if name.startswith('vmware-vmx') or name == 'mksSandbox'
            or (pid, created) in preserved
        }
        while True:
            children = {pid for pid, (_, parent, _) in members.items()
                        if parent in protected}
            if children.issubset(protected):
                break
            protected.update(children)
        preserved.update((pid, members[pid][0]) for pid in protected)

        targets, unknown = {}, []
        for pid, (created, _, name) in members.items():
            if pid in protected:
                continue
            if (pid == leader or name in ('vagrant', 'vmrun', 'sh', 'bash', 'dash')
                    or re.fullmatch(r'ruby(?:\d+(?:\.\d+)*)?', name)):
                targets[pid] = (created, name)
            else:
                unknown.append(f'{name} (PID {pid})')
        return targets, unknown

    @staticmethod
    def _signal_vagrant_controller(pid, identity, pgid, sig):
        """Recheck PID age, executable and scope immediately before signaling."""
        try:
            proc = psutil.Process(pid)
            current = (proc.create_time(), os.path.basename(proc.exe()))
            if current != identity or os.getpgid(pid) != pgid:
                raise RuntimeError(f'process identity or group changed for PID {pid}')
            # psutil also checks PID reuse when sending the signal.
            proc.send_signal(sig)
        except (psutil.NoSuchProcess, ProcessLookupError):
            pass

    def _reap_vagrant_controller(self, process, command):
        """Reap controller/helpers by PID while leaving VMware guests running.

        Unknown/unreadable group members make cleanup incomplete. Never send a
        group-wide signal: a guest monitor can outlive the Vagrant controller
        in that very same group. Remember protected identities across scans,
        including VM descendants that become reparented during cleanup.
        """
        Log.warning(
            'GOAD Kingdoms: cleaning up timed-out Vagrant controller by PID '
            f'(preserving VMware guests): {" ".join(command)}'
        )
        preserved = set()
        for sig in (signal.SIGTERM, signal.SIGKILL):
            deadline = time.monotonic() + 5
            signaled = set()
            while True:
                try:
                    process.poll()
                    members = self._vagrant_cleanup_members(process.pid)
                    previously_preserved = set(preserved)
                    targets, unknown = self._vagrant_cleanup_targets(
                        members, process.pid, preserved,
                    )
                    newly_preserved = preserved - previously_preserved
                    if newly_preserved:
                        Log.info(
                            'GOAD Kingdoms: excluding VMware guest processes from cleanup: '
                            + ', '.join(f'{members[pid][2]} (PID {pid})'
                                        for pid, _ in sorted(newly_preserved))
                        )
                    if unknown:
                        raise RuntimeError('unrecognized group members: ' + ', '.join(unknown))
                    if not targets:
                        if process.poll() is None:
                            raise RuntimeError('Vagrant leader is still running outside verified cleanup targets')
                        Log.success(
                            'GOAD Kingdoms: timed-out Vagrant controller fully reaped; '
                            'VMware guest processes preserved'
                        )
                        return True
                    for pid, identity in targets.items():
                        key = (pid, identity)
                        if key not in signaled:
                            self._signal_vagrant_controller(pid, identity, process.pid, sig)
                            signaled.add(key)
                except (psutil.Error, OSError, RuntimeError) as exc:
                    Log.error(f'GOAD Kingdoms: Vagrant cleanup incomplete; {exc}')
                    return False
                if time.monotonic() >= deadline:
                    break
                time.sleep(0.2)
        Log.error(
            'GOAD Kingdoms: timed-out Vagrant controller is still alive; '
            'refusing to race a second lifecycle action'
        )
        return False

    def _run_vagrant_bounded(self, args, timeout):
        """Run Vagrant in a dedicated group; selectively reap it on timeout."""
        if not getattr(self, '_last_bounded_vagrant_reaped', True):
            Log.error('GOAD Kingdoms: previous Vagrant cleanup is incomplete; refusing another action')
            return False
        command = [self.command.vagrant_bin] + args
        Log.info(f'GOAD_NOMAD: running bounded command: {" ".join(command)}')
        self._last_bounded_vagrant_reaped = True

        try:
            process = subprocess.Popen(
                command,
                cwd=self.path,
                start_new_session=True,
            )
        except OSError as exc:
            Log.error(f'GOAD Kingdoms: failed to start {" ".join(command)}: {exc}')
            return False

        try:
            return process.wait(timeout=timeout) == 0
        except subprocess.TimeoutExpired:
            Log.warning(
                f'GOAD_NOMAD: {" ".join(command)} exceeded {timeout}s; '
                'cleaning up its controller while preserving VMware guests'
            )
            self._last_bounded_vagrant_reaped = self._reap_vagrant_controller(
                process,
                command,
            )
            return False

    def _wait_machine_stopped(self, machine, timeout=120):
        """Wait until VMware no longer reports ``machine`` as running."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            running = self._running_instance_vms()
            if running is None:
                return False
            if machine not in running:
                return True
            time.sleep(3)
        return False

    def _stop_machine_via_vmware(self, machine):
        """Request local guest shutdown, retaining the bounded hard fallback."""
        vmx = self._vmx_path(machine)
        if not vmx:
            Log.error(f'GOAD Kingdoms: cannot locate VMX for shutdown fallback: {machine}')
            return False

        Log.info(f'GOAD Kingdoms: requesting local VMware Tools soft shutdown for {machine}')
        try:
            soft = subprocess.run(
                ['vmrun', '-T', 'ws', 'stop', vmx, 'soft'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                timeout=45,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            Log.warning(f'GOAD Kingdoms: VMware soft stop failed for {machine}: {exc}')
        else:
            detail = soft.stderr.strip() or soft.stdout.strip()
            if detail:
                Log.warning(f'GOAD Kingdoms: VMware soft stop for {machine}: {detail}')

        # Even a timed-out vmrun may have delivered the shutdown request.
        if self._wait_machine_stopped(machine, 60):
            Log.success(f'GOAD Kingdoms: {machine} completed VMware soft shutdown')
            return True
        running = self._running_instance_vms()
        if running is None:
            Log.error('GOAD Kingdoms: cannot verify VMware state; refusing hard shutdown')
            return False
        if machine not in running:
            return True

        Log.warning(
            f'GOAD Kingdoms: {machine} did not stop softly; '
            'using VMware hard stop as the final fallback'
        )
        try:
            hard = subprocess.run(
                ['vmrun', '-T', 'ws', 'stop', vmx, 'hard'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
                timeout=30,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            Log.error(f'GOAD Kingdoms: VMware hard stop failed for {machine}: {exc}')
            return False

        if self._wait_machine_stopped(machine, 30):
            Log.success(f'GOAD Kingdoms: {machine} stopped by VMware hard fallback')
            return True

        detail = hard.stderr.strip() or hard.stdout.strip()
        if detail:
            Log.error(f'GOAD Kingdoms: VMware hard stop for {machine}: {detail}')
        Log.error(f'GOAD Kingdoms: {machine} is still running after VMware hard fallback')
        return False

    def _stop_failed_windows_guest_cleanly(self, machine):
        """Stop a recoverable Windows guest without hard-powering it off first.

        Older StefanScherer Windows Server 2016 boxes can reach the desktop while
        VMware Tools/WSMan becomes unhealthy after an unconditional ``halt -f``.
        At this point ``_ensure_vmware_tools`` has already proved WinRM/Tools
        readiness, so prefer an in-guest Windows shutdown. If the transport tears
        down before returning, VMware power state remains authoritative. A VMware
        Tools soft stop is the second graceful path; forced Vagrant halt is only
        the final bounded fallback.
        """
        port = self._winrm_forwarded_port(machine)
        if port and self._wait_winrm_ready(port, 30):
            Log.info(f'GOAD Kingdoms: requesting graceful in-guest shutdown for {machine}')
            try:
                self._winrm_session(port).run_ps(
                    "shutdown.exe /s /t 0 /f | Out-Null"
                )
            except Exception as exc:
                # A successful shutdown normally destroys WinRM before pywinrm
                # receives a response. Power state below decides success.
                Log.warning(
                    f'GOAD Kingdoms: {machine} shutdown command interrupted WinRM: {exc}'
                )

            if self._wait_machine_stopped(machine, 120):
                Log.success(f'GOAD Kingdoms: {machine} completed graceful Windows shutdown')
                return True

        vmx = self._vmx_path(machine)
        if vmx:
            Log.warning(
                f'GOAD Kingdoms: {machine} did not stop through WinRM; '
                'trying VMware Tools soft shutdown'
            )
            try:
                soft = subprocess.run(
                    ['vmrun', '-T', 'ws', 'stop', vmx, 'soft'],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    check=False,
                    timeout=45,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                Log.warning(f'GOAD Kingdoms: VMware soft stop failed for {machine}: {exc}')
            else:
                if soft.returncode == 0 and self._wait_machine_stopped(machine, 120):
                    Log.success(f'GOAD Kingdoms: {machine} completed VMware soft shutdown')
                    return True
                detail = soft.stderr.strip() or soft.stdout.strip()
                if detail:
                    Log.warning(f'GOAD Kingdoms: VMware soft stop for {machine}: {detail}')

        Log.warning(
            f'GOAD Kingdoms: graceful shutdown paths did not stop {machine}; '
            'using bounded forced halt as final fallback'
        )
        if not self._run_vagrant_bounded(['halt', machine, '-f'], timeout=45):
            Log.error(f'GOAD Kingdoms: forced halt failed for {machine}')
            return False
        if not self._wait_machine_stopped(machine, 60):
            Log.error(f'GOAD Kingdoms: {machine} is still running after forced halt')
            return False
        return True

    def _ensure_vmware_tools(self, machine):
        """Allow one reporting repair per Windows installation readiness check.

        Keep the inherited installer and failed-up recovery authoritative. This
        context is deliberately absent from installed start/stop operations.
        """
        if self.lab_name != 'GOAD' or machine not in self.goad_nomad_windows:
            return super()._ensure_vmware_tools(machine)
        previous = getattr(self, '_tools_reporting_context', None)
        self._tools_reporting_context = {'machine': machine, 'restart_attempted': False}
        try:
            return super()._ensure_vmware_tools(machine)
        finally:
            self._tools_reporting_context = previous

    def _poll_guest_ip_bounded(self, vmx, timeout):
        """Bound each local query as well as the overall polling window."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                result = subprocess.run(
                    ['vmrun', '-T', 'ws', 'getGuestIPAddress', vmx],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, check=False, timeout=min(10, remaining),
                )
                if result.returncode == 0:
                    try:
                        address = ipaddress.IPv4Address(result.stdout.strip())
                    except ipaddress.AddressValueError:
                        pass
                    else:
                        if not (address.is_link_local or address.is_loopback
                                or address.is_unspecified or address.is_multicast):
                            Log.success(f'GOAD_NOMAD: VMware guest IP reporting healthy ({address})')
                            return True
            except subprocess.TimeoutExpired:
                pass
            except OSError:
                return False
            time.sleep(max(0, min(5, deadline - time.monotonic())))
        return False

    def _restart_tools_reporting(self, machine, vmx):
        """Restart the existing guest service over authenticated forwarded WinRM.

        This repairs the observed host/guest reporting disagreement, without
        assigning a lab IP, provisioning Windows, or accepting a failed up.
        """
        try:
            ports = subprocess.run(
                [self.command.vagrant_bin, 'port', machine], cwd=self.path,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, check=False, timeout=15,
            )
            match = re.search(r'5985\s+\(guest\)\s+=>\s+(\d+)\s+\(host\)', ports.stdout)
            if ports.returncode != 0 or match is None:
                return False
            port = int(match.group(1))
            if not 0 < port < 65536:
                return False
            Log.warning(
                f'GOAD Kingdoms: {machine} guest IP reporting stalled; '
                'trying one VMTools service restart through authenticated WinRM'
            )
            result = self._winrm_session(port).run_ps(r'''
$ErrorActionPreference = 'Stop'
$svc = Get-Service -Name VMTools -ErrorAction Stop
if (-not (Test-Path 'C:\Program Files\VMware\VMware Tools\vmtoolsd.exe')) {
    throw 'VMware Tools executable is missing'
}
if ($svc.Status -ne 'Stopped') {
    $svc.Stop()
    $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
}
$svc.Start()
$svc.WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
Write-Output 'GOAD_VMTOOLS_RESTARTED'
''')
            if result.status_code != 0 or b'GOAD_VMTOOLS_RESTARTED' not in result.std_out:
                return False
            # The guest command must succeed AND the host must observe an IP.
            # Direct inventory WinRM remains a separate gate before Ansible.
            if self._poll_guest_ip_bounded(vmx, 60) and self._guest_tools_healthy(port):
                Log.success(f'GOAD Kingdoms: {machine} VMTools reporting recovered after service restart')
                return True
        except Exception as exc:
            Log.warning(f'GOAD Kingdoms: VMTools reporting repair failed for {machine}: {type(exc).__name__}')
        return False

    def _wait_guest_ip(self, vmx, timeout=180):
        context = getattr(self, '_tools_reporting_context', None)
        if context is None:
            return super()._wait_guest_ip(vmx, timeout)
        if self._poll_guest_ip_bounded(vmx, timeout):
            return True
        if context['restart_attempted']:
            return False
        # Set before invoking WinRM: errors must not allow repeated restarts.
        context['restart_attempted'] = True
        return self._restart_tools_reporting(context['machine'], vmx)

    def _recover_failed_windows_vagrant_up(self, machine):
        """Recover a failed fresh Windows ``vagrant up`` deterministically.

        A failed first bring-up does not necessarily mean VMware Tools are
        absent. Fresh StefanScherer guests can already have healthy Tools and a
        working forwarded WinRM endpoint while Vagrant's VMware guest channel
        still fails during adapter/provisioner setup.

        Recovery therefore preserves the now-proven guest state: shut Windows
        down gracefully first, verify VMware reports it stopped, then execute one
        bounded ``vagrant up --provision`` cycle. Finally re-prove VMware Tools
        and authenticated WinRM readiness before allowing installation to move to
        the next machine.
        """
        Log.warning(
            f'GOAD Kingdoms: {machine} first Vagrant bring-up failed despite '
            'recoverable guest readiness; starting a clean recovery provision cycle'
        )

        if not self._stop_failed_windows_guest_cleanly(machine):
            Log.error(
                f'GOAD Kingdoms: could not stop {machine} safely after failed Vagrant bring-up'
            )
            return False

        if not self._run_vagrant_bounded(['up', machine, '--provision'], timeout=600):
            Log.error(
                f'GOAD Kingdoms: {machine} failed the bounded Vagrant --provision recovery cycle'
            )
            return False

        if not self._ensure_vmware_tools(machine):
            Log.error(
                f'GOAD Kingdoms: {machine} completed Vagrant recovery but VMware Tools/WinRM '
                'did not return healthy'
            )
            return False

        Log.success(
            f'GOAD Kingdoms: {machine} completed a clean failed-bring-up recovery provision cycle'
        )
        return True

    def start_vm(self, vm_name):
        """Start one installed guest, plus its router dependency when needed."""
        if self.lab_name != 'GOAD':
            return super().start_vm(vm_name)
        if vm_name not in self.goad_nomad_windows + ['GOAD-ROUTER']:
            Log.error(f'GOAD Kingdoms: unknown instance machine: {vm_name}')
            return False
        # Share preflight, sudo keepalive and finally-based mode restoration.
        return self.start(vm_name=vm_name)

    def stop_vm(self, vm_name):
        """Stop one instance guest locally; preserve routing for live Windows."""
        if self.lab_name != 'GOAD':
            return super().stop_vm(vm_name)
        if vm_name not in self.goad_nomad_windows + ['GOAD-ROUTER']:
            Log.error(f'GOAD Kingdoms: unknown instance machine: {vm_name}')
            return False
        if not getattr(self, '_last_bounded_vagrant_reaped', True):
            Log.error('GOAD Kingdoms: an earlier Vagrant controller was not reaped; refusing concurrent VM changes')
            return False
        running = self._running_instance_vms()
        if running is None:
            return False
        if vm_name not in running:
            Log.success(f'GOAD Kingdoms: {vm_name} is already stopped')
            return True
        if vm_name == 'GOAD-ROUTER' and any(name in running for name in self.goad_nomad_windows):
            Log.error('GOAD Kingdoms: Windows guests are still running; use stop for the whole range or stop them before the router')
            return False
        return self._stop_machine_via_vmware(vm_name)

    def stop(self):
        """Shut down members, then DCs, then the router without Vagrant NAT."""
        if self.lab_name != 'GOAD':
            return super().stop()
        if not getattr(self, '_last_bounded_vagrant_reaped', True):
            Log.error('GOAD Kingdoms: an earlier Vagrant controller was not reaped; refusing concurrent VM changes')
            return False
        running = self._running_instance_vms()
        if running is None:
            return False
        if not running:
            Log.success('GOAD_NOMAD: all instance VMs are already stopped')
            return True

        Log.info('GOAD Kingdoms: local shutdown; Windows members first, domain controllers next, router last')
        # The canonical roster lists DCs before member servers/workstations.
        for machine in reversed(self.goad_nomad_windows):
            if machine in running:
                self._stop_machine_via_vmware(machine)

        remaining = self._running_instance_vms()
        if remaining is None:
            return False
        windows_remaining = [name for name in remaining if name in self.goad_nomad_windows]
        if windows_remaining:
            Log.error('GOAD Kingdoms: Windows shutdown incomplete; keeping router available: ' + ', '.join(windows_remaining))
            return False
        if 'GOAD-ROUTER' in remaining:
            self._stop_machine_via_vmware('GOAD-ROUTER')

        remaining = self._running_instance_vms()
        if remaining is None:
            return False
        if remaining:
            Log.error('GOAD Kingdoms: shutdown incomplete; still running: ' + ', '.join(remaining))
            return False
        Log.success('GOAD Kingdoms: all instance VMs stopped and VMware state verified (no Vagrant NAT communicator)')
        return True

    def install(self):
        """Bring up a segmented GOAD instance with fail-closed Windows recovery."""
        if self.lab_name != 'GOAD':
            return super().install()
        if not getattr(self, '_last_bounded_vagrant_reaped', True):
            Log.error('GOAD Kingdoms: previous Vagrant cleanup is incomplete; refusing guest bring-up')
            return False

        # This override owns the complete Kingdoms bring-up path, so it must
        # explicitly retain the inherited host-network preflight.  Without it,
        # a missing host-address helper/timer was discovered only after every
        # guest had spent minutes coming up and provisioning routes were finally
        # enabled.  Fail (or repair the host setup) before touching any VM.
        if not self.prepare_install():
            Log.error(
                'GOAD Kingdoms: segmented VMware host-network preflight failed; '
                'no guest bring-up was attempted'
            )
            return False

        if not self._sync_goad_nomad_inventories():
            return False

        if not self._sync_goad_nomad_vagrantfile_compatibility():
            return False

        # Bring up the router independently so a Windows guest failure cannot
        # prevent creation of the routing plane. Linux keeps the normal SSH path.
        Log.info('GOAD_NOMAD: bringing up segmented router')
        if not self._bring_up_router():
            Log.error('GOAD_NOMAD: failed to bring up GOAD-ROUTER')
            return False

        # A fresh Windows box can fail its first VMware/Vagrant guest operation
        # for two different reasons: Tools may genuinely be absent, or Tools may
        # already be healthy while Vagrant's guest-communication/provisioner
        # transition is still unstable. _ensure_vmware_tools() covers the first
        # case and proves baseline guest readiness for both. Any failed first
        # vagrant up then gets one clean graceful-stop -> up --provision recovery.
        for machine in self.goad_nomad_windows:
            Log.info(f'GOAD_NOMAD: bringing up {machine}')
            first_up = self.command.run_vagrant(['up', machine], self.path)

            if not self._ensure_vmware_tools(machine):
                return False

            if not first_up:
                if not self._recover_failed_windows_vagrant_up(machine):
                    Log.error(
                        f'GOAD_NOMAD: {machine} still failed after clean Vagrant recovery'
                    )
                    return False

        # The host has no vmnet20/vmnet30 adapters, so local Ansible must
        # temporarily reach those protected networks through GOAD-ROUTER after
        # Vagrant has brought the complete instance up.
        route_script = GoadPath.get_script_file('provisioning-routes.sh')
        if not os.path.isfile(route_script):
            Log.error(f'GOAD_NOMAD provisioning route helper not found: {route_script}')
            return False

        Log.info('GOAD_NOMAD: enabling temporary host routes for local Ansible provisioning')
        route_result = subprocess.run(
            ['sudo', '-n', 'bash', route_script, 'enable'],
            check=False,
        )
        if route_result.returncode != 0:
            Log.error('GOAD_NOMAD: failed to enable temporary provisioning routes')
            return False

        Log.warning(
            'GOAD_NOMAD: provisioning routes are temporary and must be removed before exercise mode'
        )
        return True

    def _start_existing_instance(self, vm_name=None):
        """Power on an installed range without any Vagrant NAT communicator.

        Only temporarily open the existing routed management plane. The caller
        restores exercise isolation in a finally block, including on failure.
        Installation/repair remains an explicit, separate Vagrant operation.
        """
        if self.get_runtime_mode() not in ('exercise', 'provisioning'):
            Log.error('GOAD Kingdoms: no recorded installed mode; complete installation before using start')
            return False
        if vm_name is not None and vm_name not in self.goad_nomad_windows + ['GOAD-ROUTER']:
            Log.error(f'GOAD Kingdoms: unknown instance machine: {vm_name}')
            return False
        vmxs = {name: self._vmx_path(name) for name in self.goad_nomad_windows}
        if not all(vmxs.values()) or not self._vmx_path('GOAD-ROUTER'):
            Log.error('GOAD Kingdoms: installed VM files are missing; start will not recreate or provision guests')
            return False
        if not self._sync_goad_nomad_inventories():
            return False
        if not self._sync_goad_nomad_vagrantfile_compatibility():
            return False
        if not self._bring_up_router():
            return False

        if vm_name == 'GOAD-ROUTER':
            return True
        if vm_name is not None:
            vmxs = {vm_name: vmxs[vm_name]}

        # Use the router's management NIC to establish routes BEFORE checking
        # protected-zone Windows addresses. Windows NAT settings are untouched.
        if not self._apply_router_policy('provisioning'):
            return False
        if not self._enable_provisioning_routes():
            return False
        running = self._running_instance_vms()
        if running is None:
            return False
        for machine, vmx in vmxs.items():
            if machine in running:
                continue
            Log.info(f'GOAD Kingdoms: powering on {machine} locally (no Vagrant NAT discovery)')
            try:
                result = subprocess.run(
                    ['vmrun', '-T', 'ws', 'start', vmx, 'nogui'],
                    check=False, timeout=60,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                Log.error(f'GOAD Kingdoms: local power-on failed for {machine}: {exc}')
                return False
            if result.returncode != 0:
                Log.error(f'GOAD Kingdoms: local power-on failed for {machine}')
                return False

        # Reassert .254 after VMware has finished preparing all guest adapters.
        if not self._enable_provisioning_routes():
            return False
        deadline = time.monotonic() + 600
        for machine in vmxs:
            host = self.management_hosts[machine]
            remaining = int(deadline - time.monotonic())
            if remaining <= 0:
                Log.error('GOAD Kingdoms: installed range management readiness budget exhausted')
                return False
            Log.info(f'GOAD Kingdoms: verifying {machine} directly at {host}:5986')
            if not self._wait_lab_winrm_ready(machine, host, timeout=min(300, remaining)):
                return False
        Log.success('GOAD Kingdoms: requested installed guests ready over local management; no NAT communicator used')
        return True

    def _bring_up_router(self):
        """Installed ranges use local power-on and deterministic management SSH.

        A recorded mode identifies an existing managed deployment. An unknown
        or fresh deployment retains the Vagrant provisioning path. Never fall
        back to NAT after a management failure and obscure the original error.
        """
        if self.get_runtime_mode() not in ('exercise', 'provisioning'):
            return self.command.run_vagrant(['up', 'GOAD-ROUTER'], self.path)

        vmx = self._vmx_path('GOAD-ROUTER')
        if not vmx:
            Log.error('GOAD Kingdoms: installed router VMX is missing; refusing to recreate it during start')
            return False
        running = self._running_instance_vms()
        if running is None:
            return False
        try:
            if 'GOAD-ROUTER' not in running:
                result = subprocess.run(
                    ['vmrun', '-T', 'ws', 'start', vmx, 'nogui'],
                    check=False, timeout=60,
                )
                if result.returncode != 0:
                    Log.error('GOAD Kingdoms: local router power-on failed')
                    return False

            # VMware can recreate the host interfaces during power-on. Repair
            # synchronously, then validate before using the router's .1 address.
            repair = subprocess.run(
                ['sudo', '-n', 'systemctl', 'restart',
                 'goad-nomad-vmnet-hostaddrs.service'],
                check=False, timeout=50,
            )
            checker = self._script('check-vmware-networks.sh')
            ssh = self._script('router-ssh.sh')
            if repair.returncode != 0 or checker is None or ssh is None:
                return False
            if subprocess.run(['bash', checker], check=False, timeout=30).returncode != 0:
                return False

            Log.info('GOAD Kingdoms: waiting for router management SSH at 10.4.99.1:22')
            deadline = time.monotonic() + 180
            while time.monotonic() < deadline:
                try:
                    ready = subprocess.run(
                        ['bash', ssh,
                         'test "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 && '
                         'sudo -n systemctl is-active --quiet nftables'],
                        env=self._provider_env(), check=False, timeout=15,
                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                        text=True,
                    )
                    if ready.returncode == 0:
                        Log.success('GOAD Kingdoms: router management ready without NAT discovery')
                        return True
                except subprocess.TimeoutExpired:
                    pass
                time.sleep(3)
        except (OSError, subprocess.TimeoutExpired) as exc:
            Log.error(f'GOAD Kingdoms: local router startup failed: {exc}')
            return False

        Log.error(
            'GOAD Kingdoms: router management did not become ready within 180s; '
            'check vmnet99, the router SSH service/key and nftables. '
            'No NAT fallback or router reprovisioning was attempted.'
        )
        return False

    def prepare_install(self):
        # This method is the first provider hook executed by the hardened
        # install/start/ws01 paths, before GOAD-ROUTER or any Windows guest is
        # powered on. Refuse to create a duplicate-MAC condition before VMware
        # has an opportunity to register the conflicting adapter. Require the
        # operator to prime sudo before entering the lifecycle as well.
        if not self._check_segmented_instance_conflicts():
            return False
        if not self._require_cached_sudo():
            return False
        return super().prepare_install()

    def set_runtime_mode(self, mode):
        # Re-check immediately before every provisioning/exercise transition.
        # This covers long-running starts where the sudo timestamp may have
        # expired since prepare_install() and prevents the compatibility mode
        # controller from ever becoming an interactive password prompt.
        if self.is_goad_nomad_segmented() and not self._require_cached_sudo():
            return False
        return super().set_runtime_mode(mode)
